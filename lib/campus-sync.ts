// 校园事务监控系统对接：
// - 增量拉取（updated_since）+ status=all 感知完成/取消
// - 本地勾选完成 → 回写上游（带 revision 版本校验，412 自动重试一次）
import { getDb, nowLocal } from "./db";

const PROJECT = "校园事务";
const SYNC_INTERVAL_MS = 10 * 60 * 1000;

interface UpstreamTask {
  task_id: string;
  revision: number;
  title: string;
  description: string;
  action_text?: string;
  category?: string;
  status: string; // open | completed | cancelled
  due_at: string | null;
  due_date: string | null;
  time_text?: string;
  updated_at: string;
  sources?: {
    group_alias: string;
    text?: string;
    media?: string[];
  }[];
}

/** 从 CAMPUS_API_URL 解析 base 与 token */
function conf(): { base: string; token: string } | null {
  const raw = process.env.CAMPUS_API_URL;
  if (!raw) return null;
  try {
    const u = new URL(raw);
    return {
      base: u.origin,
      token: u.searchParams.get("token") ?? "",
    };
  } catch {
    return null;
  }
}

/** ISO 时间 → Asia/Shanghai 本地 "YYYY-MM-DD HH:mm"（与库内格式一致） */
function toLocal(s: string): string | null {
  const d = new Date(s);
  if (isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")} ${get("hour")}:${get("minute")}`;
}

/** 今天 00:00（Asia/Shanghai），用于同步任务的起始时间 */
function todayStart(): string {
  const d = toLocal(new Date().toISOString());
  return d ? `${d.slice(0, 10)} 00:00` : nowLocal().slice(0, 10) + " 00:00";
}

/** 上游任务 → 本地 note / dueAt / startAt */
function mapTask(t: UpstreamTask, token: string) {
  // 截止时间：精确时间优先；只有日期 → 当天 23:59
  let dueAt: string | null = null;
  if (t.due_at) dueAt = toLocal(t.due_at);
  else if (t.due_date) dueAt = `${t.due_date} 23:59`;
  // 有截止日期的同步任务：开始时间按今天算
  const startAt = dueAt ? todayStart() : null;

  const parts: string[] = [];
  if (t.description?.trim()) parts.push(t.description.trim());
  if (t.action_text?.trim()) parts.push(`行动：${t.action_text.trim()}`);
  if (t.time_text?.trim()) parts.push(`原文时间：${t.time_text.trim()}`);
  const src = t.sources?.[0];
  if (src?.group_alias) parts.push(`来源：${src.group_alias}`);
  // 群消息原文（多来源去重，完整保留）
  const texts = [...new Set(
    (t.sources ?? []).map((s) => s.text?.trim()).filter((x): x is string => !!x)
  )];
  for (const text of texts) {
    parts.push(`—— 群消息原文 ——\n${text}`);
  }
  // 图片：/media 开头拼 base + token；http 直链直接用
  for (const s of t.sources ?? []) {
    for (const m of s.media ?? []) {
      const url = m.startsWith("http")
        ? m
        : `${conf()?.base ?? ""}${m}?token=${token}`;
      parts.push(`图片：${url}`);
    }
  }

  // 类别 → 优先级：考试/作业/报名默认高优先
  const highPri = ["exam", "assignment", "registration"].includes(
    t.category ?? ""
  );

  return {
    dueAt,
    startAt,
    note: parts.join("\n"),
    done: t.status === "open" ? 0 : 1,
    priority: highPri ? "high" : "normal",
  };
}

export interface SyncResult {
  added: number;
  updated: number;
  completed: number;
  total: number;
  incremental: boolean;
  error?: string;
}

let lastResult: (SyncResult & { at: string }) | null = null;
// 上次全量同步的上游时间戳（增量游标）
let lastUpstreamAt: string | null = null;

export function lastSyncResult() {
  return lastResult;
}

export async function syncCampusTasks(): Promise<SyncResult> {
  const c = conf();
  const result: SyncResult = {
    added: 0,
    updated: 0,
    completed: 0,
    total: 0,
    incremental: !!lastUpstreamAt,
  };
  if (!c) {
    result.error = "未配置 CAMPUS_API_URL";
    lastResult = { ...result, at: nowLocal() };
    return result;
  }

  // 上游网络不稳定：拉取重试最多 3 次
  let res: Response | null = null;
  let lastErr: unknown = null;
  for (let attempt = 0; attempt < 3 && !res; attempt++) {
    try {
      const params = new URLSearchParams({ token: c.token, status: "all" });
      if (lastUpstreamAt) params.set("updated_since", lastUpstreamAt);
      const r = await fetch(`${c.base}/api/todo/v1/tasks?${params}`, {
        signal: AbortSignal.timeout(20000),
      });
      if (!r.ok) throw new Error(`上游 ${r.status}`);
      res = r;
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
  if (!res) {
    result.error = lastErr instanceof Error ? lastErr.message : String(lastErr);
    lastResult = { ...result, at: nowLocal() };
    return result;
  }

  try {
    const data = (await res.json()) as {
      generated_at?: string;
      tasks?: UpstreamTask[];
    };
    const upstream = data.tasks ?? [];
    result.total = upstream.length;
    if (data.generated_at) lastUpstreamAt = data.generated_at;

    if (!upstream.length) {
      lastResult = { ...result, at: nowLocal() };
      return result;
    }

    const db = getDb();
    const findByExt = db.prepare(
      "SELECT id, external_rev, done FROM tasks WHERE external_id = ?"
    );
    const insert = db.prepare(
      `INSERT INTO tasks (title, note, start_at, due_at, priority, project, external_id, external_rev, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const update = db.prepare(
      `UPDATE tasks SET title = ?, note = ?, start_at = ?, due_at = ?, priority = ?, external_rev = ?,
        done = ?, done_at = CASE WHEN ? = 1 AND done = 0 THEN ? ELSE done_at END,
        updated_at = ?
       WHERE external_id = ?`
    );

    for (const t of upstream) {
      if (!t.task_id || !t.title) continue;
      const m = mapTask(t, c.token);
      const existing = findByExt.get(t.task_id) as
        | { id: number; external_rev: number | null; done: number }
        | undefined;

      if (!existing) {
        if (m.done) continue; // 已完成/已取消的历史任务不导入
        insert.run(
          t.title, m.note, m.startAt, m.dueAt, m.priority, PROJECT,
          t.task_id, t.revision, nowLocal(), nowLocal()
        );
        result.added++;
      } else if ((existing.external_rev ?? -1) < t.revision) {
        update.run(
          t.title, m.note, m.startAt, m.dueAt, m.priority, t.revision,
          m.done, m.done, nowLocal(), nowLocal(), t.task_id
        );
        if (m.done && !existing.done) result.completed++;
        else result.updated++;
      }
    }
  } catch (e) {
    result.error = e instanceof Error ? e.message : "同步失败";
  }

  lastResult = { ...result, at: nowLocal() };
  return result;
}

/**
 * 回写上游状态（本地勾选完成/取消完成时调用）。
 * 带 revision 版本校验；412（版本过旧）→ 用 current_revision 重试一次。
 * 失败不抛异常（本地状态已生效，下次全量同步会校准）。
 */
export async function writebackStatus(
  taskId: string,
  revision: number | null,
  done: boolean
): Promise<{ ok: boolean; newRev?: number }> {
  const c = conf();
  if (!c) return { ok: false };
  const status = done ? "completed" : "open";

  async function attempt(version: number | null) {
    return fetch(`${c!.base}/api/todo/v1/tasks/${taskId}/status?token=${c!.token}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(
        version !== null ? { status, version } : { status }
      ),
      signal: AbortSignal.timeout(10000),
    });
  }

  try {
    let res = await attempt(revision);
    if (res.status === 412) {
      const d = (await res.json().catch(() => null)) as {
        current_revision?: number;
      } | null;
      if (d?.current_revision !== undefined) {
        res = await attempt(d.current_revision);
      }
    }
    if (!res.ok) return { ok: false };
    const d = (await res.json().catch(() => null)) as {
      version?: number;
    } | null;
    // 更新本地 revision，避免下次同步误判
    if (d?.version !== undefined) {
      getDb()
        .prepare("UPDATE tasks SET external_rev = ? WHERE external_id = ?")
        .run(d.version, taskId);
    }
    return { ok: true, newRev: d?.version };
  } catch {
    return { ok: false };
  }
}

/** 服务启动时调用：立即同步一次，之后每 10 分钟同步 */
export function startCampusSyncLoop() {
  if (!process.env.CAMPUS_API_URL) return;
  const g = globalThis as unknown as { __campusSyncStarted?: boolean };
  if (g.__campusSyncStarted) return;
  g.__campusSyncStarted = true;
  syncCampusTasks().catch(() => {});
  setInterval(() => syncCampusTasks().catch(() => {}), SYNC_INTERVAL_MS).unref();
}
