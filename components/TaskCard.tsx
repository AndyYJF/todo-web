"use client";

import { motion } from "motion/react";
import type { Task } from "@/lib/types";
import { durationHours, fmtShort, isOverdue } from "@/lib/datetime";
import { IconClock, IconEdit } from "./icons";

/** 圆形勾选框：描边画勾 + 填充弹跳 */
function Checkbox({ done }: { done: boolean }) {
  return (
    <span
      className={`relative mt-[3px] w-[18px] h-[18px] rounded-full border-[1.5px] grid place-items-center shrink-0 transition-colors duration-200 ${
        done
          ? "bg-ink border-ink"
          : "border-ink/25 group-hover:border-ink/60 bg-transparent"
      }`}
    >
      <svg viewBox="0 0 12 12" className="w-2.5 h-2.5">
        <motion.path
          d="M2 6.2 4.8 9 10 3.2"
          fill="none"
          stroke="#faf9f5"
          strokeWidth={1.8}
          strokeLinecap="round"
          strokeLinejoin="round"
          initial={false}
          animate={{ pathLength: done ? 1 : 0, opacity: done ? 1 : 0 }}
          transition={{ duration: 0.25, ease: "easeOut" }}
        />
      </svg>
    </span>
  );
}

export default function TaskCard({
  task,
  index = 0,
  onOpen,
  onToggle,
  onEdit,
}: {
  task: Task;
  index?: number;
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
  onEdit?: (t: Task) => void;
}) {
  const overdue = isOverdue(task);
  const dur = durationHours(task.startAt, task.dueAt);
  const done = task.done === 1;

  const meta: { text: string; cls?: string }[] = [];
  if (overdue) meta.push({ text: "已超期", cls: "text-danger font-semibold" });
  if (task.priority === "high")
    meta.push({ text: "高优先", cls: "text-warn font-medium" });
  if (task.quick === 1) meta.push({ text: "快速任务" });
  if (task.project) meta.push({ text: task.project });
  if (task.startAt || task.dueAt) {
    const range = `${fmtShort(task.startAt)}${
      task.startAt && task.dueAt ? " → " : ""
    }${fmtShort(task.dueAt)}`;
    meta.push({
      text: dur !== null ? `${range} · ${dur}h` : range,
    });
  }

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{
        opacity: 0,
        scale: 0.96,
        y: -8,
        transition: { duration: 0.3, ease: [0.4, 0, 1, 1] },
      }}
      transition={{
        type: "spring",
        stiffness: 320,
        damping: 32,
        delay: Math.min(index * 0.04, 0.35),
        layout: { type: "spring", stiffness: 340, damping: 38, mass: 1 },
      }}
      onClick={() => onOpen(task)}
      className={`group flex items-start gap-3.5 bg-card border rounded-2xl px-5 py-4 cursor-pointer shadow-card hover:shadow-lift hover:-translate-y-px transition-[box-shadow,transform,border-color] duration-200 ${
        overdue ? "border-danger/30" : "border-line hover:border-ink/15"
      } ${done ? "opacity-50" : ""}`}
    >
      <motion.button
        whileTap={{ scale: 0.75 }}
        onClick={(e) => {
          e.stopPropagation();
          onToggle(task);
        }}
        aria-label={done ? "取消完成" : "标记完成"}
        className="shrink-0"
      >
        <Checkbox done={done} />
      </motion.button>

      <div className="flex-1 min-w-0">
        <div
          className={`text-[15px] leading-snug break-words transition-colors ${
            done ? "line-through text-ink-soft" : ""
          }`}
        >
          {task.title}
        </div>

        {meta.length > 0 && (
          <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-ink-soft">
            {overdue && (
              <span className="px-1.5 py-px rounded-md bg-danger-soft text-danger font-medium">
                已超期
              </span>
            )}
            {meta
              .filter((m) => m.text !== "已超期")
              .map((m, i) => (
                <span key={i} className={`inline-flex items-center gap-1 ${m.cls ?? ""}`}>
                  {(m.text.includes("→") || m.text.includes("h")) && <IconClock />}
                  <span className="tnum">{m.text}</span>
                  {i < meta.filter((x) => x.text !== "已超期").length - 1 && (
                    <span className="text-ink-soft/40 ml-1">·</span>
                  )}
                </span>
              ))}
          </div>
        )}
      </div>

      {onEdit && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onEdit(task);
          }}
          aria-label="编辑"
          className="mt-0.5 p-1.5 rounded-lg text-ink-soft/0 group-hover:text-ink-soft hover:!text-accent hover:bg-paper transition-colors shrink-0"
        >
          <IconEdit />
        </button>
      )}
    </motion.div>
  );
}
