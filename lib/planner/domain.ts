import { isPlannerDate } from "./dates";

export class PlannerError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly current?: unknown,
  ) { super(message); }
}

export function invalid(message: string): never {
  throw new PlannerError(400, "invalid_input", message);
}

export function record(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) invalid("需要 JSON 对象");
  return input as Record<string, unknown>;
}

export function requireDate(input: unknown): string {
  if (!isPlannerDate(input)) invalid("日期必须是有效的 YYYY-MM-DD");
  return input;
}

export function requireVersion(input: unknown, minimum = 1): number {
  if (typeof input !== "number" || !Number.isSafeInteger(input) || input < minimum) {
    invalid("版本号无效");
  }
  return input;
}

export function requireId(input: unknown): string {
  if (typeof input !== "string" || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(input)) {
    invalid("操作或条目 ID 必须是 UUID");
  }
  return input.toLowerCase();
}

export const ARCHIVE_LIMIT_BYTES = 500_000_000;

export type Course = {
  key: string;
  date: string;
  title: string;
  location: string;
  startsAt: string;
  endsAt: string;
  allDay: boolean;
};

export type PlanItem = {
  id: string;
  version: number;
  title: string;
  startTime: string | null;
  endTime: string | null;
  status: "pending" | "done" | "unfinished";
  note: string;
  todoId: number | null;
};

export type DayPayload = { courses: Course[]; items: PlanItem[] };

export function applyFields(item: PlanItem, input: unknown): PlanItem {
  const fields = record(input);
  const known = ["title", "startTime", "endTime", "status", "note", "todoId"];
  if (Object.keys(fields).length === 0 || Object.keys(fields).some((key) => !known.includes(key))) {
    invalid("请提交有效的条目字段");
  }
  const result = { ...item };
  if ("title" in fields) {
    if (typeof fields.title !== "string" || !fields.title.trim() || fields.title.length > 160) invalid("标题需为 1–160 字符");
    result.title = fields.title.trim();
  }
  if ("note" in fields) {
    if (typeof fields.note !== "string" || Buffer.byteLength(fields.note) > 8192) invalid("备注最多 8192 字节");
    result.note = fields.note;
  }
  if ("status" in fields) {
    if (fields.status !== "pending" && fields.status !== "done" && fields.status !== "unfinished") invalid("条目状态无效");
    result.status = fields.status;
  }
  if ("todoId" in fields) {
    result.todoId = fields.todoId === null ? null : requireVersion(fields.todoId);
  }
  for (const key of ["startTime", "endTime"] as const) {
    if (!(key in fields)) continue;
    const value = fields[key];
    if (value !== null && (typeof value !== "string" || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value))) {
      invalid("时间必须是 HH:mm 或 null");
    }
    result[key] = value;
  }
  if ((result.startTime === null) !== (result.endTime === null) ||
      (result.startTime && result.endTime && result.endTime <= result.startTime)) {
    invalid("开始与结束时间必须成对填写，且结束晚于开始");
  }
  return result;
}
