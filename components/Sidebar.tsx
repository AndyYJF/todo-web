"use client";

import { motion } from "motion/react";
import {
  IconCalendar,
  IconFolder,
  IconGantt,
  IconList,
  IconPin,
  IconSettings,
  IconSun,
} from "./icons";

export type ViewKey =
  | "today"
  | "all"
  | "calendar"
  | "gantt"
  | "projects"
  | "pinned"
  | "settings";

const ITEMS: { key: ViewKey; label: string; Icon: typeof IconSun }[] = [
  { key: "today", label: "今日", Icon: IconSun },
  { key: "all", label: "全部任务", Icon: IconList },
  { key: "calendar", label: "日历", Icon: IconCalendar },
  { key: "gantt", label: "甘特图", Icon: IconGantt },
  { key: "projects", label: "项目跟踪", Icon: IconFolder },
  { key: "pinned", label: "置顶磁贴", Icon: IconPin },
  { key: "settings", label: "设置", Icon: IconSettings },
];

export default function Sidebar({
  view,
  todayCount,
  projectsCount,
  lastSync,
  open,
  onNavigate,
}: {
  view: ViewKey;
  todayCount: number;
  projectsCount: number;
  lastSync: Date | null;
  /** 移动端抽屉开关 */
  open: boolean;
  onNavigate: (v: ViewKey) => void;
}) {
  const badges: Partial<Record<ViewKey, number>> = {
    today: todayCount,
    projects: projectsCount,
  };

  return (
    <aside
      className={`fixed md:sticky inset-y-0 left-0 z-50 md:z-auto w-60 shrink-0 h-screen bg-card border-r border-line flex flex-col px-4 py-7 transition-transform duration-200 ease-out ${
        open ? "translate-x-0" : "-translate-x-full md:translate-x-0"
      }`}
    >
      {/* 字标 */}
      <div className="px-3 mb-10">
        <div className="font-display text-[28px] leading-none tracking-tight">
          Todo<span className="text-accent">.</span>
        </div>
        <div className="mt-1.5 text-[10px] uppercase tracking-[0.22em] text-ink-soft">
          Personal Tasks
        </div>
      </div>

      <div className="px-3 mb-2 text-[10px] uppercase tracking-[0.22em] text-ink-soft/70">
        工作台
      </div>
      <nav className="space-y-0.5">
        {ITEMS.map(({ key, label, Icon }) => {
          const active = view === key;
          const badge = badges[key];
          return (
            <button
              key={key}
              onClick={() => onNavigate(key)}
              className={`relative w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-[13.5px] transition-colors duration-150 ${
                active ? "text-paper" : "text-ink-soft hover:text-ink"
              }`}
            >
              {active && (
                <motion.span
                  layoutId="nav-pill"
                  transition={{ type: "spring", stiffness: 500, damping: 40 }}
                  className="absolute inset-0 bg-ink rounded-lg"
                />
              )}
              <span className="relative z-10 flex items-center gap-2.5 flex-1">
                <Icon className="w-[17px] h-[17px]" />
                <span className="flex-1 text-left font-medium">{label}</span>
                {badge != null && badge > 0 && (
                  <span
                    className={`text-[11px] tnum rounded-full min-w-[20px] h-5 grid place-items-center px-1.5 ${
                      active ? "bg-paper/20 text-paper" : "bg-paper text-ink-soft"
                    }`}
                  >
                    {badge}
                  </span>
                )}
              </span>
            </button>
          );
        })}
      </nav>

      <div className="mt-auto px-3 flex items-center gap-2 text-[11px] text-ink-soft/80">
        <span className="relative flex h-1.5 w-1.5">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-500 opacity-60" />
          <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-600" />
        </span>
        <span className="tnum">
          {lastSync
            ? `已同步 ${String(lastSync.getHours()).padStart(2, "0")}:${String(lastSync.getMinutes()).padStart(2, "0")}:${String(lastSync.getSeconds()).padStart(2, "0")}`
            : "同步中…"}
        </span>
        <button
          onClick={async () => {
            await fetch("/api/logout", { method: "POST" });
            window.location.href = "/login";
          }}
          className="ml-auto hover:text-ink transition-colors"
        >
          退出
        </button>
      </div>
    </aside>
  );
}
