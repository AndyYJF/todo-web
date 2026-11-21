import type { Course, PlanItem } from "./domain";

export type PlanDay = {
  date: string; today: string; openFrom: string; serverTime: number; revision: number;
  timetableRevision: number; archived: boolean; courses: Course[]; items: PlanItem[];
};
export type PlanHistory = {
  items: { date: string; archivedAt: number; itemCount: number; doneCount: number }[];
  nextBefore: string | null;
  bytes: number;
  limitBytes: number;
  earliestDate: string | null;
  revision: number;
};

export const planStatusLabel: Record<PlanItem["status"], string> = {
  pending: "未记录", done: "已完成", unfinished: "未完成",
};

export type ImportPreview = {
  checksum: string; baseVersion: number; effectiveFrom: string; serverTime: number;
  from: string; through: string; count: number; added: number; updated: number;
  removed: number; sample: Course[];
};
export type SchoolWeek = {
  current: { week: number; phase: string; source: string; officialUrl: string | null } | null;
};

export class PlannerResponseError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string, readonly current?: PlanItem) {
    super(message);
  }
  get uncertain() { return this.status === 0 || this.status === 408 || this.status >= 500; }
}

export async function plannerRequest<T>(path = "", body?: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
  let response: Response;
  try {
    const timeout = AbortSignal.timeout(20_000);
    response = await fetch("/api/planner" + path, {
      cache: "no-store", signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
      ...(body ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {}),
    });
  } catch {
    throw new PlannerResponseError("连接失败，请检查网络后重试", 0);
  }
  const data = await response.json().catch(() => null);
  if (response.status === 401) {
    window.location.assign("/login");
    throw new PlannerResponseError("会话已失效，请重新登录", 401);
  }
  if (!response.ok) throw new PlannerResponseError(
    data?.error ?? (response.status === 404 ? "当前站点尚未启用规划明天" : "规划服务暂时不可用"),
    response.status, data?.code, data?.current,
  );
  if (!data) throw new PlannerResponseError("服务返回了无效响应，请重试", 0);
  return data as T;
}

export function plannerError(error: unknown): string {
  return error instanceof Error ? error.message : "操作未完成，请重试";
}

export const MAX_PLANNER_IMPORT = 1_048_576;
export type TimelineEntry =
  | { kind: "course"; course: Course; start: number; end: number }
  | { kind: "item"; item: PlanItem; start: number; end: number; overlap: boolean }
  | { kind: "gap"; start: number; end: number };

function minute(value: string) {
  const [hour, minutes] = value.split(":").map(Number);
  return hour * 60 + minutes;
}

export function formatMinute(value: number) {
  const pad = (part: number) => String(part).padStart(2, "0");
  return pad(Math.floor(value / 60)) + ":" + pad(value % 60);
}

export function timeline(day: PlanDay): TimelineEntry[] {
  const courses: TimelineEntry[] = day.courses.filter((course) => !course.allDay).map((course) => ({
    kind: "course", course,
    start: course.startsAt.slice(0, 10) < day.date ? 0 : minute(course.startsAt.slice(11, 16)),
    end: course.endsAt.slice(0, 10) > day.date ? 1440 : minute(course.endsAt.slice(11, 16)),
  }));
  const booked: TimelineEntry[] = [...courses];
  for (const item of day.items) {
    if (!item.startTime || !item.endTime) continue;
    const start = minute(item.startTime), end = minute(item.endTime);
    booked.push({ kind: "item", item, start, end,
      overlap: courses.some((course) => start < course.end && course.start < end) });
  }
  booked.sort((a, b) => a.start - b.start || a.end - b.end);
  let freeFrom = 8 * 60;
  const freeUntil = 22 * 60;
  const entries: TimelineEntry[] = [];
  for (const block of booked) {
    const end = Math.min(block.start, freeUntil);
    if (end - freeFrom >= 15) entries.push({ kind: "gap", start: freeFrom, end });
    entries.push(block);
    freeFrom = Math.max(freeFrom, block.end);
  }
  if (freeUntil - freeFrom >= 15) entries.push({ kind: "gap", start: freeFrom, end: freeUntil });
  return entries;
}
