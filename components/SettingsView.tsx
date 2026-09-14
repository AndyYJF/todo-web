"use client";

import { useState } from "react";
import type { Task } from "@/lib/types";
import { isOverdue } from "@/lib/datetime";

export default function SettingsView({ tasks }: { tasks: Task[] }) {
  const done = tasks.filter((t) => t.done).length;
  const overdue = tasks.filter((t) => isOverdue(t)).length;
  const [syncing, setSyncing] = useState(false);
  const [syncMsg, setSyncMsg] = useState("");

  async function syncCampus() {
    setSyncing(true);
    setSyncMsg("");
    try {
      const res = await fetch("/api/sync", { method: "POST" });
      const d = await res.json();
      setSyncMsg(
        d.error
          ? `同步失败：${d.error}`
          : `上游 ${d.total} 条：新增 ${d.added}、更新 ${d.updated}、完成 ${d.completed}`
      );
    } catch {
      setSyncMsg("同步失败：网络异常");
    } finally {
      setSyncing(false);
    }
  }

  function exportJson() {
    // 加 BOM：Excel/记事本打开时按 UTF-8 识别，中文不乱码
    const blob = new Blob(["\uFEFF" + JSON.stringify(tasks, null, 2)], {
      type: "application/json;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `todo-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  const stats: [number, string, string?][] = [
    [tasks.length, "总任务"],
    [done, "已完成"],
    [overdue, "已超期", "text-danger"],
  ];

  return (
    <div className="max-w-xl">
      <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
        设置
      </h1>

      <section className="bg-card border border-line rounded-2xl shadow-card p-6 mb-4">
        <div className="text-[10px] uppercase tracking-[0.22em] text-ink-soft mb-4">
          统计
        </div>
        <div className="grid grid-cols-3 gap-3 text-center">
          {stats.map(([n, label, cls]) => (
            <div key={label} className="bg-paper rounded-xl py-4">
              <div className={`font-display text-[36px] leading-none tnum ${cls ?? ""}`}>
                {n}
              </div>
              <div className="text-xs text-ink-soft mt-1.5">{label}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="bg-card border border-line rounded-2xl shadow-card p-6 mb-4">
        <div className="text-[10px] uppercase tracking-[0.22em] text-ink-soft mb-4">
          校园事务
        </div>
        <div className="flex items-center gap-4">
          <div className="flex-1 text-[13px] text-ink-soft">
            对接事务监控系统，每 10 分钟自动同步，任务归入「校园事务」项目
          </div>
          <button
            onClick={syncCampus}
            disabled={syncing}
            className="bg-ink text-paper rounded-xl px-4 py-2 text-[13px] font-medium hover:bg-black disabled:opacity-40 transition-colors shrink-0"
          >
            {syncing ? "同步中…" : "立即同步"}
          </button>
        </div>
        {syncMsg && (
          <div className="mt-3 text-[12px] text-ink-soft tnum">{syncMsg}</div>
        )}
      </section>

      <section className="bg-card border border-line rounded-2xl shadow-card p-6 mb-4">
        <div className="text-[10px] uppercase tracking-[0.22em] text-ink-soft mb-2">
          数据备份
        </div>
        <p className="text-[13px] text-ink-soft mb-4 leading-relaxed">
          数据保存在服务器的 SQLite 文件里，可随时导出 JSON 备份。
        </p>
        <button
          onClick={exportJson}
          className="bg-ink text-paper rounded-xl px-5 py-2.5 text-[13px] font-medium hover:bg-black transition-colors"
        >
          导出全部任务（JSON）
        </button>
      </section>

      <section className="bg-card border border-line rounded-2xl shadow-card p-6 text-[13px] text-ink-soft leading-relaxed">
        <div className="text-[10px] uppercase tracking-[0.22em] mb-2">关于</div>
        <p>Todo 待办清单 · Next.js + SQLite（node:sqlite）</p>
        <p className="mt-1">
          数据库路径由环境变量 TODO_DB_PATH 控制，默认 ./data/todo.db
        </p>
      </section>
    </div>
  );
}
