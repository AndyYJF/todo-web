import type { DatabaseSync } from "node:sqlite";
import { DAY_MS, dateEpoch, isPlannerDate } from "./dates";
import { boundedText } from "./http";

const OFFICIAL_INDEX = "https://jwc.scu.edu.cn/cdxl.htm";
const OFFICIAL_2026 = "https://jwc.scu.edu.cn/info/1101/10727.htm";
const COMMUNITY_JSON = "https://raw.githubusercontent.com/The-Brotherhood-of-SCU/Bugaoshan/main/assets/academic_calendar.json";
const REFRESH_MS = 12 * 60 * 60 * 1000;
const RETRY_MS = 5 * 60 * 1000;

type Notice = { year: string; url: string };
type Semester = {
  year: string;
  season: "autumn" | "spring";
  weekOneSunday: string;
  weeks: number;
  examWeeks?: number[];
  practiceWeeks?: number[];
  officialUrl: string | null;
  source: "official_verified" | "bugaoshan";
};

const verified: Semester[] = [
  { year: "2026-2027", season: "autumn", weekOneSunday: "2026-08-30", weeks: 20,
    examWeeks: [19, 20], officialUrl: OFFICIAL_2026, source: "official_verified" },
  { year: "2026-2027", season: "spring", weekOneSunday: "2027-02-28", weeks: 20,
    examWeeks: [18], practiceWeeks: [19, 20], officialUrl: OFFICIAL_2026, source: "official_verified" },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validAcademicYear(year: string): boolean {
  return /^20\d{2}-20\d{2}$/.test(year) && Number(year.slice(5)) === Number(year.slice(0, 4)) + 1;
}

export function parseOfficialNotices(html: string): Notice[] {
  const notices = new Map<string, Notice>();
  const pattern = /<a\b[^>]*href=["']((?:\/)?info\/\d+\/\d+\.htm)["'][^>]*>\s*(20\d{2})\s*[-–—－]\s*(20\d{2})\s*学年四川大学校历\s*<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const year = match[2] + "-" + match[3];
    if (!validAcademicYear(year)) continue;
    notices.set(year, { year, url: new URL(match[1], OFFICIAL_INDEX).href });
  }
  if (!notices.size) throw new Error("Official calendar index layout changed");
  return [...notices.values()].sort((a, b) => b.year.localeCompare(a.year));
}

export function parseCommunitySemesters(input: unknown): Semester[] {
  if (!isRecord(input) || !Array.isArray(input.semesters) || !input.semesters.length || input.semesters.length > 100) {
    throw new Error("Academic calendar schema changed");
  }
  const result = new Map<string, Semester>();
  for (const raw of input.semesters) {
    if (!isRecord(raw)) throw new Error("Invalid semester");
    const name = raw.n ?? raw.name;
    const start = raw.s ?? raw.startDate;
    const weeks = raw.w ?? raw.totalWeeks;
    if (typeof name !== "string" || !isPlannerDate(start) ||
        typeof weeks !== "number" || !Number.isInteger(weeks) || weeks < 12 || weeks > 26) {
      throw new Error("Invalid academic week");
    }
    const match = /^(20\d{2}-20\d{2})学年([秋春])季学期$/.exec(name);
    if (!match || !validAcademicYear(match[1])) throw new Error("Invalid semester name");
    const year = match[1], season = match[2] === "秋" ? "autumn" : "spring";
    const expectedYear = season === "autumn" ? year.slice(0, 4) : year.slice(5);
    const month = Number(start.slice(5, 7));
    if (!start.startsWith(expectedYear) || !(season === "autumn" ? [8, 9] : [2, 3]).includes(month)) {
      throw new Error("Semester starts outside expected range");
    }
    const first = new Date(dateEpoch(start));
    const weekOneSunday = new Date(first.getTime() - first.getUTCDay() * DAY_MS).toISOString().slice(0, 10);
    const key = year + season;
    if (result.has(key)) throw new Error("Duplicate semester");
    result.set(key, { year, season, weekOneSunday, weeks, officialUrl: null, source: "bugaoshan" });
  }
  return [...result.values()];
}

export function teachingWeek(date: string, semesters: Semester[]) {
  for (const semester of [...semesters].sort((a, b) => b.weekOneSunday.localeCompare(a.weekOneSunday))) {
    const index = Math.floor((dateEpoch(date) - dateEpoch(semester.weekOneSunday)) / (7 * DAY_MS)) + 1;
    if (index < 1 || index > semester.weeks) continue;
    const phase = semester.examWeeks?.includes(index) ? "exam" :
      semester.practiceWeeks?.includes(index) ? "practice" : "week";
    return { ...semester, week: index, phase };
  }
  return null;
}

type CacheRow = { payload: string | null; checked_at: number; fetched_at: number | null };
const pending = new WeakMap<DatabaseSync, Map<string, Promise<void>>>();

async function source<T>(db: DatabaseSync, name: string, url: string, parse: (value: string) => T) {
  db.exec(`CREATE TABLE IF NOT EXISTS planner_academic_cache (
    source TEXT PRIMARY KEY, payload TEXT, checked_at INTEGER NOT NULL, fetched_at INTEGER
  )`);
  const select = () => db.prepare("SELECT * FROM planner_academic_cache WHERE source=?").get(name) as CacheRow | undefined;
  const existing = select();
  const now = Date.now();
  const ttl = existing?.fetched_at === existing?.checked_at ? REFRESH_MS : RETRY_MS;
  if (!existing || now - existing.checked_at >= ttl) {
    let perDb = pending.get(db);
    if (!perDb) { perDb = new Map(); pending.set(db, perDb); }
    let task = perDb.get(name);
    if (!task) {
      task = (async () => {
        try {
          const response = await fetch(url, { cache: "no-store", redirect: "error", signal: AbortSignal.timeout(5000) });
          if (!response.ok) throw new Error("Academic calendar upstream request failed");
          const payload = parse(await boundedText(response, 512 * 1024));
          db.prepare(`INSERT INTO planner_academic_cache VALUES (?, ?, ?, ?)
              ON CONFLICT(source) DO UPDATE SET payload=excluded.payload,
                checked_at=excluded.checked_at, fetched_at=excluded.fetched_at`)
            .run(name, JSON.stringify(payload), now, now);
        } catch {
          // Keep the last successful response when the upstream is unavailable or changes shape.
          db.prepare(`INSERT INTO planner_academic_cache VALUES (?, NULL, ?, NULL)
              ON CONFLICT(source) DO UPDATE SET checked_at=excluded.checked_at`).run(name, now);
        }
      })().finally(() => perDb.delete(name));
      perDb.set(name, task);
    }
    await task;
  }
  const cached = select();
  return {
    data: cached?.payload ? JSON.parse(cached.payload) as T : null,
    fetchedAt: cached?.fetched_at ? new Date(cached.fetched_at).toISOString() : null,
    stale: cached?.fetched_at == null || cached.checked_at > cached.fetched_at,
  };
}

export async function academicCalendar(db: DatabaseSync, date: string) {
  const [official, community] = await Promise.all([
    source(db, "official", OFFICIAL_INDEX, parseOfficialNotices),
    source(db, "community", COMMUNITY_JSON, (raw) => parseCommunitySemesters(JSON.parse(raw))),
  ]);
  const notices = official.data ?? [{ year: "2026-2027", url: OFFICIAL_2026 }];
  const officialByYear = new Map(notices.map((item) => [item.year, item.url]));
  const semesters = (community.data ?? []).filter((item) =>
    !verified.some((fixed) => item.year === fixed.year && item.season === fixed.season))
    .map((item) => ({ ...item, officialUrl: officialByYear.get(item.year) ?? null }));
  return {
    date, timeZone: "Asia/Shanghai", current: teachingWeek(date, [...semesters, ...verified]),
    notices, sources: {
      official: { url: OFFICIAL_INDEX, fetchedAt: official.fetchedAt, stale: official.stale },
      community: { url: COMMUNITY_JSON, fetchedAt: community.fetchedAt, stale: community.stale },
    },
  };
}
