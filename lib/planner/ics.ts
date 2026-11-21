import ical, { type VEvent } from "node-ical";
import { DAY_MS, dateTimeInBusinessZone, isPlannerDate } from "./dates";
import { invalid, PlannerError, type Course } from "./domain";
import { sha256 } from "./store";

export const MAX_ICS_BYTES = 1_048_576;
const MAX_EVENTS = 2000;
const MAX_OCCURRENCES = 5000;
const MAX_EVENT_SPAN = 31 * DAY_MS;

function textValue(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (value && typeof value === "object" && "val" in value && typeof value.val === "string") return value.val.trim();
  return "";
}

function validateAndNormalize(text: string) {
  // RFC 5545 folded lines are continuations. Floating times use the planning zone.
  const unfolded = text.replace(/^\uFEFF/u, "").replace(/\r?\n[ \t]/g, "").trim();
  if (!/^BEGIN:VCALENDAR\r?\n/i.test(unfolded) || !/\r?\nEND:VCALENDAR$/i.test(unfolded)) {
    invalid("请导入有效的 iCalendar 文件");
  }
  let events = 0;
  let insideEvent = false;
  const masters = new Set<string>();
  const overrides = new Set<string>();
  let uid = "", recurrenceId = "", startDate = "", rule: Map<string, string> | null = null;
  const lines: string[] = [];
  for (let line of unfolded.split(/\r?\n/)) {
    if (/^BEGIN:VEVENT$/i.test(line)) {
      if (insideEvent || ++events > MAX_EVENTS) invalid("课表课程数量超限或结构无效");
      insideEvent = true;
      uid = ""; recurrenceId = ""; startDate = ""; rule = null;
    } else if (/^END:VEVENT$/i.test(line)) {
      if (!insideEvent || !uid || !startDate) invalid("部分课程缺少标识或开始时间");
      if (rule) {
        const count = Number(rule.get("COUNT"));
        const until = rule.get("UNTIL");
        const interval = Number(rule.get("INTERVAL") ?? 1);
        const periodDays = rule.get("FREQ") === "DAILY" ? 1 : rule.get("FREQ") === "WEEKLY" ? 7 : 31;
        if (!Number.isInteger(interval) || interval < 1 || interval > 12) invalid("重复课程的间隔无效");
        if (until) {
          const ymd = (value: string) => [value.slice(0, 4), value.slice(4, 6), value.slice(6, 8)].join("-");
          const span = Date.parse(ymd(until)) - Date.parse(ymd(startDate));
          if (!isPlannerDate(ymd(until)) || !Number.isFinite(span) || span < 0 || span > 366 * DAY_MS) {
            invalid("重复课表请限定在一个学年内，或导出逐次展开的 .ics");
          }
        } else if (!Number.isInteger(count) || count < 1 || (count - 1) * periodDays * interval > 366 ||
                   rule.get("FREQ") === "MONTHLY" || [...rule.keys()].some((key) =>
                     key.startsWith("BY") && !(key === "BYDAY" && rule?.get("FREQ") === "WEEKLY"))) {
          invalid("该重复规则需提供一年内的结束日期，或导出逐次展开的 .ics");
        }
      }
      const identities = recurrenceId ? overrides : masters;
      const id = recurrenceId ? JSON.stringify([uid, recurrenceId]) : uid;
      if (identities.has(id)) invalid("课表包含重复的课程事件标识");
      identities.add(id);
      insideEvent = false;
    } else if (insideEvent) {
      const colon = line.indexOf(":");
      const property = line.slice(0, colon).split(";")[0].toUpperCase();
      const value = line.slice(colon + 1);
      if (property === "UID") uid = value.trim();
      if (property === "RECURRENCE-ID") recurrenceId = value;
      if (property === "DTSTART") startDate = value;

      if (property === "RDATE" || property === "EXRULE") {
        invalid("课表含暂不支持的额外重复日期，请导出逐次展开的 .ics");
      }
      if (property === "RRULE") {
        const parts = new Map(value.toUpperCase().split(";").map((part) => part.split("=") as [string, string]));
        if (!["DAILY", "WEEKLY", "MONTHLY"].includes(parts.get("FREQ") ?? "") ||
            ["BYSECOND", "BYMINUTE", "BYHOUR"].some((key) => parts.has(key))) {
          invalid("重复规则过密或不适用于课程导入");
        }
        if (!parts.has("UNTIL") && !parts.has("COUNT")) invalid("请为重复课程设定结束日期或次数后重新导出");
        rule = parts;
      }
      if (["DTSTART", "DTEND", "RECURRENCE-ID", "EXDATE"].includes(property)) {
        const header = line.slice(0, colon);
        for (const dateValue of value.split(",")) {
          const match = /^(20\d{2})(\d{2})(\d{2})(?:T([01]\d|2[0-3])([0-5]\d)([0-5]\d)Z?)?$/.exec(dateValue);
          if (!match || !isPlannerDate([match[1], match[2], match[3]].join("-"))) invalid("课表包含无法识别的日期或时间");
        }
        if (!/;TZID=/i.test(header) && /^\d{8}T\d{6}(?:,\d{8}T\d{6})*$/.test(value)) {
          line = header + ";TZID=Asia/Shanghai:" + value;
        }
      }
    }
    lines.push(line);
  }
  if (insideEvent || !events) invalid("未找到完整的课程事件");
  return { normalized: lines.join("\r\n"), eventCount: events, masterCount: masters.size };
}

function addOccurrence(courses: Map<string, Course>, event: VEvent, start: Date, end: Date, allDay: boolean) {
  const title = textValue(event.summary);
  const location = textValue(event.location);
  if (!title || title.length > 240 || location.length > 400 ||
      !Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) ||
      end.getTime() <= start.getTime() || end.getTime() - start.getTime() > MAX_EVENT_SPAN) {
    invalid("课程标题、地点或起止时间不符合导入要求");
  }
  // All-day calendar dates should not be shifted by an instant's timezone.
  const startsAt = allDay ? start.toISOString().slice(0, 10) + "T00:00:00" : dateTimeInBusinessZone(start);
  const endsAt = allDay ? end.toISOString().slice(0, 10) + "T00:00:00" : dateTimeInBusinessZone(end);
  const first = Date.parse(startsAt + "Z");
  const until = Date.parse(endsAt + "Z");
  for (let day = Date.parse(startsAt.slice(0, 10) + "T00:00:00Z"); day < until; day += DAY_MS) {
    const date = new Date(day).toISOString().slice(0, 10);
    if (!isPlannerDate(date)) invalid("课表事件超出支持日期范围");
    const key = sha256(JSON.stringify([event.uid, startsAt, date]));
    const course: Course = { key, date, title, location, startsAt, endsAt, allDay };
    const existing = courses.get(key);
    if (existing && JSON.stringify(existing) !== JSON.stringify(course)) invalid("同一课程实例有冲突的数据");
    courses.set(key, course);
    if (courses.size > MAX_OCCURRENCES || until - first > MAX_EVENT_SPAN) invalid("课表展开数量或跨度超限");
  }
}

export async function parseCourseCalendar(text: string) {
  if (Buffer.byteLength(text) > MAX_ICS_BYTES) throw new PlannerError(413, "ics_too_large", "课表文件最大 1 MiB");
  const { normalized, eventCount, masterCount } = validateAndNormalize(text);
  const courses = new Map<string, Course>();
  try {
    const components = await ical.async.parseICS(normalized);
    const events = Object.values(components).filter((part): part is VEvent => part?.type === "VEVENT");
    if (events.length !== masterCount) invalid("部分课程的重复例外或标识无法识别");
    for (const event of events) {
      if (event.status === "CANCELLED") continue;
      if (event.rrule) {
        const to = new Date(event.start.getTime() + 398 * DAY_MS);
        const result = ical.expandRecurringEvent(event, { from: event.start, to, maxIterations: 1200 });
        if (result.some((instance) => instance.start.getTime() - event.start.getTime() > 368 * DAY_MS)) {
          invalid("重复课表请限定在一个学年内，或导出逐次展开的 .ics");
        }
        for (const instance of result) {
          if (instance.event.status !== "CANCELLED") addOccurrence(courses, instance.event, instance.start, instance.end, instance.isFullDay);
        }
      } else {
        if (!event.end) invalid("课程缺少结束时间");
        addOccurrence(courses, event, event.start, event.end, event.datetype === "date");
      }
    }
  } catch (error) {
    if (error instanceof PlannerError) throw error;
    invalid("iCalendar 解析失败，请检查导出文件");
  }
  if (!courses.size) invalid("没有可导入的课程");
  return { courses: [...courses.values()].sort((a, b) => a.date.localeCompare(b.date) ||
    a.startsAt.localeCompare(b.startsAt) || a.key.localeCompare(b.key)),
    checksum: sha256(text), eventCount };
}
