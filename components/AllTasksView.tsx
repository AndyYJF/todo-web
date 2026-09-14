"use client";

import { useMemo, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task } from "@/lib/types";
import TaskCard from "./TaskCard";

type Tab = "pending" | "done" | "all";
const TABS: { key: Tab; label: string }[] = [
  { key: "pending", label: "进行中" },
  { key: "done", label: "已完成" },
  { key: "all", label: "全部" },
];

export default function AllTasksView({
  tasks,
  projects,
  onOpen,
  onToggle,
}: {
  tasks: Task[];
  projects: string[];
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
}) {
  const [tab, setTab] = useState<Tab>("pending");
  const [project, setProject] = useState("");

  const filtered = useMemo(
    () =>
      tasks.filter((t) => {
        if (tab === "pending" && t.done) return false;
        if (tab === "done" && !t.done) return false;
        if (project && t.project !== project) return false;
        return true;
      }),
    [tasks, tab, project]
  );

  return (
    <div className="max-w-2xl">
      <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
        全部任务
      </h1>

      <div className="flex items-center gap-3 mb-6 flex-wrap">
        {/* 分段控件：滑动指示器 */}
        <div className="flex bg-card border border-line rounded-xl p-1 shadow-card">
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`relative px-4 py-1.5 rounded-lg text-[13px] transition-colors duration-150 ${
                tab === t.key ? "text-paper" : "text-ink-soft hover:text-ink"
              }`}
            >
              {tab === t.key && (
                <motion.span
                  layoutId="tab-pill"
                  transition={{ type: "spring", stiffness: 500, damping: 40 }}
                  className="absolute inset-0 bg-ink rounded-lg"
                />
              )}
              <span className="relative z-10 font-medium">{t.label}</span>
            </button>
          ))}
        </div>
        <select
          value={project}
          onChange={(e) => setProject(e.target.value)}
          className="bg-card border border-line rounded-xl px-3.5 py-2 text-[13px] outline-none shadow-card"
        >
          <option value="">所有项目</option>
          {projects.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
        <span className="text-xs text-ink-soft tnum ml-auto">
          {filtered.length} 项
        </span>
      </div>

      <div className="space-y-2.5">
        <AnimatePresence mode="popLayout">
          {filtered.map((t, i) => (
            <TaskCard
              key={t.id}
              task={t}
              index={i}
              onOpen={onOpen}
              onToggle={onToggle}
            />
          ))}
        </AnimatePresence>
        {filtered.length === 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="pt-20 text-center"
          >
            <div className="font-display italic text-2xl text-ink-soft/70">
              Nothing here.
            </div>
            <div className="mt-2 text-[13px] text-ink-soft">
              没有符合条件的任务
            </div>
          </motion.div>
        )}
      </div>
    </div>
  );
}
