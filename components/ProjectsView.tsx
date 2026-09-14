"use client";

import { useMemo } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task } from "@/lib/types";
import TaskCard from "./TaskCard";

export default function ProjectsView({
  tasks,
  onOpen,
  onToggle,
}: {
  tasks: Task[];
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
}) {
  const groups = useMemo(() => {
    const m = new Map<string, Task[]>();
    for (const t of tasks) {
      const key = t.project || "未分组";
      if (!m.has(key)) m.set(key, []);
      m.get(key)!.push(t);
    }
    return [...m.entries()].sort(
      (a, b) =>
        b[1].filter((t) => !t.done).length - a[1].filter((t) => !t.done).length
    );
  }, [tasks]);

  return (
    <div className="max-w-2xl">
      <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
        项目跟踪
      </h1>
      <div className="space-y-5">
        {groups.map(([name, list]) => {
          const done = list.filter((t) => t.done).length;
          const pct = list.length ? Math.round((done / list.length) * 100) : 0;
          const pending = list.filter((t) => !t.done);
          return (
            <section
              key={name}
              className="bg-card border border-line rounded-2xl shadow-card p-5"
            >
              <div className="flex items-baseline gap-3 mb-2.5">
                <h2 className="font-semibold text-[15px]">{name}</h2>
                <span className="text-xs text-ink-soft tnum">
                  {done}/{list.length}
                </span>
                <span className="font-display italic text-xl text-accent ml-auto tnum">
                  {pct}%
                </span>
              </div>
              <div className="h-1 bg-paper rounded-full overflow-hidden mb-4">
                <motion.div
                  initial={{ width: 0 }}
                  animate={{ width: `${pct}%` }}
                  transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
                  className="h-full bg-accent rounded-full"
                />
              </div>
              <div className="space-y-2">
                <AnimatePresence mode="popLayout">
                  {pending.map((t, i) => (
                    <TaskCard
                      key={t.id}
                      task={t}
                      index={i}
                      onOpen={onOpen}
                      onToggle={onToggle}
                    />
                  ))}
                </AnimatePresence>
                {pending.length === 0 && (
                  <div className="font-display italic text-lg text-ink-soft/60 py-1">
                    All done.
                  </div>
                )}
              </div>
            </section>
          );
        })}
        {groups.length === 0 && (
          <div className="pt-20 text-center">
            <div className="font-display italic text-2xl text-ink-soft/70">
              No projects yet.
            </div>
            <div className="mt-2 text-[13px] text-ink-soft">
              还没有任务，去「今日」创建一个吧
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
