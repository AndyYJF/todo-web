export const DAY_MS = 86_400_000;
export const UTC_PLUS_8_MS = 8 * 60 * 60 * 1000;

export function businessDate(instant = Date.now()): string {
  return new Date(instant + UTC_PLUS_8_MS).toISOString().slice(0, 10);
}

export function dateTimeInBusinessZone(instant: Date): string {
  return new Date(instant.getTime() + UTC_PLUS_8_MS).toISOString().slice(0, 19);
}

export function dateEpoch(date: string): number {
  return Date.parse(date + "T00:00:00Z");
}

export function isPlannerDate(input: unknown): input is string {
  if (typeof input !== "string" || !/^20\d\d-\d\d-\d\d$/.test(input)) return false;
  const day = dateEpoch(input);
  return Number.isFinite(day) && new Date(day).toISOString().slice(0, 10) === input;
}

// Before 04:00 (UTC+8), yesterday is still open for edits.
export function archiveBefore(now = Date.now()): string {
  return businessDate(now - 4 * 60 * 60 * 1000);
}
