// 纯函数，客户端 / 服务端通用（禁止 import node:*）

/** 本地时间 'YYYY-MM-DD HH:mm' */
export function nowLocal(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(
    d.getHours()
  )}:${p(d.getMinutes())}`;
}

/** 今天 23:59 */
export function todayEnd(): string {
  return nowLocal().slice(0, 10) + " 23:59";
}

export function todayStr(): string {
  return nowLocal().slice(0, 10);
}

export function isOverdue(t: { dueAt: string | null; done: number }): boolean {
  return t.done === 0 && !!t.dueAt && t.dueAt < nowLocal();
}

/** 'YYYY-MM-DD HH:mm' → 'MM/dd HH:mm' */
export function fmtShort(s: string | null): string {
  if (!s) return "";
  return s.slice(5).replace("-", "/");
}

/** 开始→截止的时长（小时，保留 1 位小数） */
export function durationHours(
  startAt: string | null,
  dueAt: string | null
): number | null {
  if (!startAt || !dueAt) return null;
  const a = new Date(startAt.replace(" ", "T")).getTime();
  const b = new Date(dueAt.replace(" ", "T")).getTime();
  if (Number.isNaN(a) || Number.isNaN(b) || b <= a) return null;
  return Math.round(((b - a) / 36e5) * 10) / 10;
}

const WEEKDAYS = ["日", "一", "二", "三", "四", "五", "六"];

/** 首页大标题：'9月9日' 与 '星期三' */
export function todayHeader(): { big: string; weekday: string; year: number } {
  const d = new Date();
  return {
    big: `${d.getMonth() + 1} 月 ${d.getDate()} 日`,
    weekday: `星期${WEEKDAYS[d.getDay()]}`,
    year: d.getFullYear(),
  };
}
