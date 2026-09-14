import { getDb, nowLocal, todayEnd } from "./db";
import type { Task, TaskInput, TaskPatch } from "./types";

interface Row {
  id: number;
  title: string;
  note: string;
  start_at: string | null;
  due_at: string | null;
  done: number;
  done_at: string | null;
  priority: string;
  project: string;
  quick: number;
  pinned: number;
  external_id: string | null;
  external_rev: number | null;
  created_at: string;
  updated_at: string;
}

function toTask(r: Row): Task {
  return {
    id: r.id,
    title: r.title,
    note: r.note,
    startAt: r.start_at,
    dueAt: r.due_at,
    done: r.done as 0 | 1,
    doneAt: r.done_at,
    priority: r.priority as Task["priority"],
    project: r.project,
    quick: r.quick as 0 | 1,
    pinned: r.pinned as 0 | 1,
    externalId: r.external_id,
    externalRev: r.external_rev,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export type TaskView = "today" | "all" | "upcoming" | "done" | "pinned";

export function listTasks(opts: {
  view?: TaskView;
  project?: string;
}): Task[] {
  const db = getDb();
  const clauses: string[] = [];
  const args: (string | number)[] = [];

  switch (opts.view ?? "today") {
    case "today":
      // 未完成 且（无截止日期 或 截止不晚于今天）→ 含超期
      clauses.push("done = 0", "(due_at IS NULL OR due_at <= ?)");
      args.push(todayEnd());
      break;
    case "upcoming":
      clauses.push("done = 0", "due_at > ?");
      args.push(todayEnd());
      break;
    case "done":
      clauses.push("done = 1");
      break;
    case "pinned":
      clauses.push("pinned = 1");
      break;
    case "all":
      break;
  }
  if (opts.project) {
    clauses.push("project = ?");
    args.push(opts.project);
  }

  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const rows = db
    .prepare(
      `SELECT * FROM tasks ${where}
       ORDER BY done ASC,
                due_at IS NULL ASC, due_at ASC,
                priority = 'high' DESC, priority = 'normal' DESC,
                id DESC`
    )
    .all(...args) as unknown as Row[];
  return rows.map(toTask);
}

export function listProjects(): string[] {
  const rows = getDb()
    .prepare(
      "SELECT DISTINCT project FROM tasks WHERE project != '' ORDER BY project"
    )
    .all() as unknown as { project: string }[];
  return rows.map((r) => r.project);
}

export function getTask(id: number): Task | null {
  const row = getDb().prepare("SELECT * FROM tasks WHERE id = ?").get(id) as
    | Row
    | undefined;
  return row ? toTask(row) : null;
}

export function createTask(input: TaskInput): Task {
  const now = nowLocal();
  const res = getDb()
    .prepare(
      `INSERT INTO tasks (title, note, start_at, due_at, priority, project, quick, pinned, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      input.title.trim(),
      input.note ?? "",
      input.startAt ?? null,
      input.dueAt ?? null,
      input.priority ?? "normal",
      input.project ?? "",
      input.quick ? 1 : 0,
      input.pinned ? 1 : 0,
      now,
      now
    );
  return getTask(Number(res.lastInsertRowid))!;
}

const PATCHABLE: Record<string, string> = {
  title: "title",
  note: "note",
  startAt: "start_at",
  dueAt: "due_at",
  priority: "priority",
  project: "project",
};

const PRIORITIES = new Set(["low", "normal", "high"]);

export function updateTask(id: number, patch: TaskPatch): Task | null {
  const sets: string[] = [];
  const args: (string | number | null)[] = [];

  for (const [key, col] of Object.entries(PATCHABLE)) {
    if (key in patch) {
      const v = patch[key as keyof TaskPatch];
      // 枚举校验：非法 priority 直接忽略
      if (key === "priority" && !PRIORITIES.has(String(v))) continue;
      sets.push(`${col} = ?`);
      args.push(typeof v === "string" || v === null ? v : String(v));
    }
  }
  for (const flag of ["quick", "pinned"] as const) {
    if (patch[flag] !== undefined) {
      sets.push(`${flag} = ?`);
      args.push(patch[flag] ? 1 : 0);
    }
  }
  if ("done" in patch && patch.done !== undefined) {
    sets.push("done = ?", "done_at = ?");
    args.push(patch.done ? 1 : 0, patch.done ? nowLocal() : null);
  }
  if (!sets.length) return getTask(id);

  sets.push("updated_at = ?");
  args.push(nowLocal(), id);
  getDb()
    .prepare(`UPDATE tasks SET ${sets.join(", ")} WHERE id = ?`)
    .run(...args);
  return getTask(id);
}

export function deleteTask(id: number): boolean {
  const res = getDb().prepare("DELETE FROM tasks WHERE id = ?").run(id);
  return res.changes > 0;
}
