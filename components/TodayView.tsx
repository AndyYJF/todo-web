"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task } from "@/lib/types";
import { todayHeader } from "@/lib/datetime";
import TaskCard from "./TaskCard";
import DateTimePicker from "./DateTimePicker";

export default function TodayView({
  tasks,
  onQuickCreate,
  onNewDetail,
  onOpen,
  onToggle,
  onEdit,
}: {
  tasks: Task[];
  onQuickCreate: (title: string, dueAt: string | null) => Promise<void>;
  onNewDetail: () => void;
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
  onEdit: (t: Task) => void;
}) {
  const [text, setText] = useState("");
  const [due, setDue] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const { big, weekday, year } = todayHeader();

  // "/" 聚焦快速添加
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const tag = (e.target as HTMLElement)?.tagName;
      if (e.key === "/" && tag !== "INPUT" && tag !== "TEXTAREA") {
        e.preventDefault();
        inputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const nextDue = tasks
    .filter((t) => t.dueAt)
    .map((t) => t.dueAt!)
    .sort()[0];

  async function submit() {
    const title = text.trim();
    if (!title) return;
    setText("");
    setDue(null);
    await onQuickCreate(title, due);
  }

  return (
    <div className="max-w-2xl">
      {/* 头部 */}
      <header className="mb-9">
        <div className="text-[10px] uppercase tracking-[0.25em] text-ink-soft mb-3">
          {weekday} · {year}
        </div>
        <h1 className="font-display text-[38px] md:text-[52px] leading-[1.05] tracking-tight">
          {big}
          <span className="text-ink-soft/60 italic">，今天的事</span>
        </h1>
        <div className="mt-3 text-[13px] text-ink-soft">
          {tasks.length > 0 ? (
            <>
              <span className="tnum">{tasks.length}</span> 项任务
              {nextDue && (
                <span className="tnum">，最近一项 {nextDue.slice(11)} 到期</span>
              )}
            </>
          ) : (
            "全部清空，享受当下"
          )}
        </div>
      </header>

      {/* 快速添加 */}
      <div className="flex items-center flex-wrap gap-2 bg-card border border-line rounded-2xl shadow-card pl-5 pr-2 py-2 mb-8 focus-within:border-ink/30 transition-colors">
        <span className="text-ink-soft text-lg leading-none select-none">+</span>
        <input
          ref={inputRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          placeholder="写点什么，回车即成任务…"
          className="flex-1 min-w-0 bg-transparent py-2 text-[15px] outline-none placeholder:text-ink-soft/60"
        />
        <DateTimePicker
          compact
          value={due}
          onChange={setDue}
          placeholder="无期限"
        />
        <kbd className="hidden sm:grid place-items-center w-6 h-6 rounded-md border border-line text-[11px] text-ink-soft bg-paper shrink-0">
          /
        </kbd>
        <AnimatePresence>
          {text.trim() && (
            <motion.button
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ duration: 0.12 }}
              onClick={submit}
              className="bg-ink text-paper rounded-xl px-4 py-2 text-[13px] font-medium hover:bg-black transition-colors shrink-0"
            >
              添加
            </motion.button>
          )}
        </AnimatePresence>
        <button
          onClick={onNewDetail}
          className="text-[13px] text-ink-soft hover:text-accent px-2 py-2 transition-colors whitespace-nowrap shrink-0"
        >
          详细任务 →
        </button>
      </div>

      {/* 任务列表 */}
      <div className="space-y-2.5">
        <AnimatePresence mode="popLayout">
          {tasks.map((t, i) => (
            <TaskCard
              key={t.id}
              task={t}
              index={i}
              onOpen={onOpen}
              onToggle={onToggle}
              onEdit={onEdit}
            />
          ))}
        </AnimatePresence>
        {tasks.length === 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="pt-20 text-center"
          >
            <div className="font-display italic text-2xl text-ink-soft/70">
              Nothing due. Breathe.
            </div>
            <div className="mt-2 text-[13px] text-ink-soft">
              今天没有待办事项
            </div>
          </motion.div>
        )}
      </div>
    </div>
  );
}
