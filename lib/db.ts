import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";

export { nowLocal, todayEnd } from "./datetime";

const dbPath =
  process.env.TODO_DB_PATH ?? path.join(process.cwd(), "data", "todo.db");
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

// 开发模式 HMR 下保持单例，避免重复打开数据库
const globalForDb = globalThis as unknown as { __todoDb?: DatabaseSync };

export function getDb(): DatabaseSync {
  if (!globalForDb.__todoDb) {
    const db = new DatabaseSync(dbPath);
    db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS tasks (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT    NOT NULL,
        note       TEXT    NOT NULL DEFAULT '',
        start_at   TEXT,
        due_at     TEXT,
        done       INTEGER NOT NULL DEFAULT 0,
        done_at    TEXT,
        priority   TEXT    NOT NULL DEFAULT 'normal',
        project    TEXT    NOT NULL DEFAULT '',
        quick      INTEGER NOT NULL DEFAULT 0,
        pinned     INTEGER NOT NULL DEFAULT 0,
        created_at TEXT    NOT NULL,
        updated_at TEXT    NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_tasks_done_due ON tasks(done, due_at);
    `);
    // 老库自动迁移：补 pinned 列
    try {
      db.exec("ALTER TABLE tasks ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0");
    } catch {
      // 列已存在
    }
    // 外部同步源（校园事务监控）
    try {
      db.exec("ALTER TABLE tasks ADD COLUMN external_id TEXT");
    } catch {
      // 列已存在
    }
    try {
      db.exec("ALTER TABLE tasks ADD COLUMN external_rev INTEGER");
    } catch {
      // 列已存在
    }
    try {
      db.exec(
        "CREATE UNIQUE INDEX idx_tasks_external ON tasks(external_id) WHERE external_id IS NOT NULL"
      );
    } catch {
      // 索引已存在
    }
    globalForDb.__todoDb = db;
  }
  return globalForDb.__todoDb;
}
