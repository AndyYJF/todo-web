"use client";

import { AnimatePresence, motion } from "motion/react";
import type { Task } from "@/lib/types";
import { durationHours, fmtShort, isOverdue } from "@/lib/datetime";
import { IconPin } from "./icons";

/** 置顶磁贴模式：置顶任务以大卡片网格呈现 */
export default function PinsView({
  tasks,
  onOpen,
  onToggle,
}: {
  tasks: Task[];
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
}) {
  const pinned = tasks.filter((t) => t.pinned === 1);

  return (
    <div className="max-w-3xl">
      <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
        置顶磁贴
      </h1>

      {pinned.length === 0 ? (
        <div className="pt-20 text-center">
          <div className="font-display italic text-2xl text-ink-soft/70">
            Nothing pinned.
          </div>
          <div className="mt-2 text-[13px] text-ink-soft">
            在任务详情里点「置顶」，它就会出现在这里
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <AnimatePresence mode="popLayout">
            {pinned.map((t, i) => {
              const overdue = isOverdue(t);
              const done = t.done === 1;
              const dur = durationHours(t.startAt, t.dueAt);
              return (
                <motion.div
                  key={t.id}
                  layout
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{
                    opacity: 0,
                    scale: 0.88,
                    transition: { duration: 0.28, ease: [0.4, 0, 1, 1] },
                  }}
                  transition={{
                    type: "spring",
                    stiffness: 300,
                    damping: 30,
                    delay: Math.min(i * 0.06, 0.35),
                    layout: { type: "spring", stiffness: 340, damping: 38, mass: 1 },
                  }}
                  onClick={() => onOpen(t)}
                  className={`group relative bg-card border rounded-2xl shadow-card hover:shadow-lift hover:-translate-y-0.5 transition-[box-shadow,transform] duration-200 p-5 cursor-pointer ${
                    overdue ? "border-danger/30" : "border-line"
                  } ${done ? "opacity-55" : ""}`}
                >
                  <IconPin className="absolute top-4 right-4 w-4 h-4 text-accent" />
                  <div
                    className={`font-display text-xl leading-snug pr-8 break-words ${
                      done ? "line-through text-ink-soft" : ""
                    }`}
                  >
                    {t.title}
                  </div>
                  <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-ink-soft">
                    {overdue && (
                      <span className="px-1.5 py-px rounded-md bg-danger-soft text-danger font-medium">
                        已超期
                      </span>
                    )}
                    {t.priority === "high" && (
                      <span className="text-warn font-medium">高优先</span>
                    )}
                    {t.project && <span>{t.project}</span>}
                    {(t.startAt || t.dueAt) && (
                      <span className="tnum">
                        {fmtShort(t.startAt)}
                        {t.startAt && t.dueAt && " → "}
                        {fmtShort(t.dueAt)}
                        {dur !== null && ` · ${dur}h`}
                      </span>
                    )}
                  </div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onToggle(t);
                    }}
                    className={`mt-4 w-full rounded-xl py-2 text-[13px] font-medium transition-colors ${
                      done
                        ? "border border-line text-ink-soft hover:bg-paper"
                        : "bg-ink text-paper hover:bg-black"
                    }`}
                  >
                    {done ? "取消完成" : "标记完成"}
                  </button>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
      )}
    </div>
  );
}
