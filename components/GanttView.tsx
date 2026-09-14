"use client";

import { useMemo } from "react";
import type { Task } from "@/lib/types";
import { isOverdue, nowLocal } from "@/lib/datetime";

const DAY_MS = 86400000;
const LABEL_W = 176; // 左侧任务名列宽 px

function toMs(s: string): number {
  return new Date(s.replace(" ", "T")).getTime();
}

/** 甘特图：横向时间条，跨度 start→due（缺省则退化为当天/现在） */
export default function GanttView({
  tasks,
  onOpen,
}: {
  tasks: Task[];
  onOpen: (t: Task) => void;
}) {
  const rows = useMemo(() => {
    const withTime = tasks.filter((t) => t.startAt || t.dueAt);
    const items = withTime.map((t) => {
      const start = t.startAt ? toMs(t.startAt) : t.dueAt ? toMs(t.dueAt) - 3600e3 : 0;
      const end = t.dueAt ? toMs(t.dueAt) : t.startAt ? toMs(t.startAt) + 3600e3 : 0;
      return { task: t, start, end: Math.max(end, start + 1800e3) };
    });
    items.sort((a, b) => a.start - b.start);
    return items;
  }, [tasks]);

  const { rangeStart, days } = useMemo(() => {
    if (!rows.length) return { rangeStart: 0, days: [] as number[] };
    const now = Date.now();
    let min = Math.min(...rows.map((r) => r.start), now);
    let max = Math.max(...rows.map((r) => r.end), now);
    // 对齐到天，前后各留 1 天
    min = Math.floor(min / DAY_MS) * DAY_MS - DAY_MS;
    max = Math.ceil(max / DAY_MS) * DAY_MS + DAY_MS;
    // 至少 7 天，至多 62 天（超出则截到最早 62 天窗口）
    if (max - min < 7 * DAY_MS) max = min + 7 * DAY_MS;
    if (max - min > 62 * DAY_MS) max = min + 62 * DAY_MS;
    const days: number[] = [];
    for (let d = min; d < max; d += DAY_MS) days.push(d);
    return { rangeStart: min, days };
  }, [rows]);

  if (!rows.length) {
    return (
      <div className="max-w-4xl">
        <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
          甘特图
        </h1>
        <div className="pt-20 text-center">
          <div className="font-display italic text-2xl text-ink-soft/70">
            No timeline yet.
          </div>
          <div className="mt-2 text-[13px] text-ink-soft">
            给任务设置开始/截止时间后，这里会出现时间条
          </div>
        </div>
      </div>
    );
  }

  const span = days.length * DAY_MS;
  const now = Date.now();
  const nowPct = ((now - rangeStart) / span) * 100;
  const todayLabel = nowLocal().slice(5, 10).replace("-", "/");

  return (
    <div className="max-w-4xl">
      <h1 className="font-display text-[40px] leading-tight tracking-tight mb-6">
        甘特图
      </h1>

      <div className="bg-card border border-line rounded-2xl shadow-card p-4 overflow-x-auto">
        <div style={{ minWidth: LABEL_W + days.length * 44 }}>
          {/* 日期刻度 */}
          <div className="flex border-b border-line pb-2 mb-1">
            <div style={{ width: LABEL_W }} className="shrink-0" />
            {days.map((d) => {
              const dt = new Date(d);
              const isToday =
                dt.toDateString() === new Date().toDateString();
              return (
                <div
                  key={d}
                  className={`flex-1 text-center text-[10px] tnum ${
                    isToday ? "text-accent font-semibold" : "text-ink-soft"
                  }`}
                >
                  {dt.getMonth() + 1}/{dt.getDate()}
                </div>
              );
            })}
          </div>

          {/* 任务行 */}
          <div className="relative">
            {/* 日边界网格线 */}
            {days.map((_, i) =>
              i === 0 ? null : (
                <div
                  key={i}
                  className="absolute top-0 bottom-0 w-px bg-line/70 pointer-events-none"
                  style={{
                    left: `calc(${LABEL_W}px + (100% - ${LABEL_W}px) * ${i / days.length})`,
                  }}
                />
              )
            )}
            {/* 今天竖线（位置 = 当前确切时间在当日列内的进度） */}
            {nowPct >= 0 && nowPct <= 100 && (
              <div
                className="absolute top-0 bottom-0 w-px bg-accent/50 z-10 pointer-events-none"
                style={{ left: `calc(${LABEL_W}px + (100% - ${LABEL_W}px) * ${nowPct / 100})` }}
              />
            )}
            {rows.map(({ task, start, end }) => {
              const overdue = isOverdue(task);
              const done = task.done === 1;
              const left = ((Math.max(start, rangeStart) - rangeStart) / span) * 100;
              const width =
                ((Math.min(end, rangeStart + span) - Math.max(start, rangeStart)) / span) * 100;
              return (
                <button
                  key={task.id}
                  onClick={() => onOpen(task)}
                  className="flex items-center w-full py-[7px] group text-left"
                >
                  <div
                    style={{ width: LABEL_W }}
                    className={`shrink-0 pr-4 text-[13px] truncate transition-colors ${
                      done
                        ? "line-through text-ink-soft"
                        : "group-hover:text-accent"
                    }`}
                  >
                    {task.title}
                  </div>
                  <div className="flex-1 relative h-5">
                    <div
                      className={`absolute top-1/2 -translate-y-1/2 h-2.5 rounded-full transition-transform group-hover:scale-y-125 ${
                        done
                          ? "bg-ink-soft/25"
                          : overdue
                            ? "bg-danger"
                            : "bg-accent"
                      }`}
                      style={{
                        left: `${left}%`,
                        width: `${Math.max(width, 1)}%`,
                      }}
                    />
                  </div>
                </button>
              );
            })}
          </div>

          <div className="mt-3 pt-3 border-t border-line flex items-center gap-4 text-[11px] text-ink-soft">
            <span className="flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-accent" /> 进行中
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-danger" /> 已超期
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-ink-soft/25" /> 已完成
            </span>
            <span className="ml-auto tnum">今天 {todayLabel}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
