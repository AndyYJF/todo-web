"use client";

import { useMemo, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task } from "@/lib/types";
import { todayStr } from "@/lib/datetime";
import TaskCard from "./TaskCard";

const WEEK_LABELS = ["一", "二", "三", "四", "五", "六", "日"];

export default function CalendarView({
  tasks,
  onOpen,
  onToggle,
}: {
  tasks: Task[];
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
}) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth());
  const [selected, setSelected] = useState<string | null>(todayStr());

  const byDay = useMemo(() => {
    const m = new Map<string, Task[]>();
    for (const t of tasks) {
      if (!t.dueAt) continue;
      const day = t.dueAt.slice(0, 10);
      if (!m.has(day)) m.set(day, []);
      m.get(day)!.push(t);
    }
    return m;
  }, [tasks]);

  function shiftMonth(delta: number) {
    const d = new Date(year, month + delta, 1);
    setYear(d.getFullYear());
    setMonth(d.getMonth());
  }

  const firstDay = new Date(year, month, 1);
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const leading = (firstDay.getDay() + 6) % 7;
  const p = (n: number) => String(n).padStart(2, "0");
  const cells: (string | null)[] = [
    ...Array<string | null>(leading).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => `${year}-${p(month + 1)}-${p(i + 1)}`),
  ];

  const today = todayStr();
  const selectedTasks = selected ? (byDay.get(selected) ?? []) : [];

  return (
    <div className="max-w-2xl">
      <div className="flex items-end gap-3 mb-6">
        <h1 className="font-display text-[40px] leading-tight tracking-tight tnum">
          {year} 年 {month + 1} 月
        </h1>
        <div className="ml-auto flex gap-1.5 pb-1.5">
          <button
            onClick={() => shiftMonth(-1)}
            className="w-8 h-8 rounded-full border border-line bg-card hover:border-ink/30 transition-colors"
          >
            ‹
          </button>
          <button
            onClick={() => {
              setYear(now.getFullYear());
              setMonth(now.getMonth());
              setSelected(today);
            }}
            className="px-3.5 h-8 rounded-full border border-line bg-card hover:border-ink/30 text-[13px] transition-colors"
          >
            今天
          </button>
          <button
            onClick={() => shiftMonth(1)}
            className="w-8 h-8 rounded-full border border-line bg-card hover:border-ink/30 transition-colors"
          >
            ›
          </button>
        </div>
      </div>

      <div className="bg-card border border-line rounded-2xl shadow-card p-4">
        <div className="grid grid-cols-7 text-center text-[10px] uppercase tracking-[0.18em] text-ink-soft pb-2">
          {WEEK_LABELS.map((w) => (
            <div key={w}>{w}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {cells.map((day, i) => {
            if (!day) return <div key={`e${i}`} />;
            const list = byDay.get(day) ?? [];
            const pending = list.filter((t) => !t.done).length;
            const isToday = day === today;
            const isSel = day === selected;
            return (
              <motion.button
                key={day}
                whileTap={{ scale: 0.92 }}
                onClick={() => setSelected(day)}
                className={`relative aspect-square rounded-xl text-[13px] tnum transition-colors duration-150 ${
                  isSel
                    ? "bg-ink text-paper"
                    : isToday
                      ? "text-accent font-semibold ring-1 ring-accent"
                      : "hover:bg-paper"
                }`}
              >
                {Number(day.slice(8))}
                {list.length > 0 && (
                  <span className="absolute bottom-1.5 left-1/2 -translate-x-1/2 flex gap-0.5">
                    {Array.from({ length: Math.min(list.length, 3) }).map(
                      (_, d) => (
                        <span
                          key={d}
                          className={`w-1 h-1 rounded-full ${
                            isSel
                              ? "bg-paper/70"
                              : pending > 0
                                ? "bg-danger"
                                : "bg-ink-soft/40"
                          }`}
                        />
                      )
                    )}
                  </span>
                )}
              </motion.button>
            );
          })}
        </div>
      </div>

      {selected && (
        <div className="mt-6">
          <div className="text-[10px] uppercase tracking-[0.22em] text-ink-soft mb-3 tnum">
            {selected} · {selectedTasks.length} 项截止
          </div>
          <div className="space-y-2.5">
            <AnimatePresence mode="popLayout">
              {selectedTasks.map((t, i) => (
                <TaskCard
                  key={t.id}
                  task={t}
                  index={i}
                  onOpen={onOpen}
                  onToggle={onToggle}
                />
              ))}
            </AnimatePresence>
          </div>
        </div>
      )}
    </div>
  );
}
