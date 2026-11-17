"use client";

import { useState } from "react";
import { motion } from "motion/react";
import type { Task } from "@/lib/types";
import { fmtShort } from "@/lib/datetime";

interface Props {
  tasks: Task[];
  onOpen: (t: Task) => void;
  onToggle: (t: Task) => void;
  onMove: (t: Task, urgent: boolean, important: boolean) => void;
  onClassify: () => Promise<void>;
  classifying: boolean;
  classifyMsg: string;
}

interface Quadrant {
  key: string;
  title: string;
  en: string;
  urgent: boolean;
  important: boolean;
  accent: string;
  bg: string;
  /** 在坐标平面中的位置 */
  pos: "tl" | "tr" | "bl" | "br";
}

// 数学象限约定：第一象限（右上）= 重要且紧急
const QUADRANTS: Quadrant[] = [
  { key: "do", title: "第一象限 · 马上做", en: "重要且紧急", urgent: true, important: true, accent: "text-danger", bg: "bg-danger/[0.06]", pos: "tr" },
  { key: "plan", title: "第二象限 · 计划做", en: "重要不紧急", urgent: false, important: true, accent: "text-accent", bg: "bg-accent/[0.06]", pos: "tl" },
  { key: "delegate", title: "第三象限 · 快速处理", en: "紧急不重要", urgent: true, important: false, accent: "text-warn", bg: "bg-warn/[0.06]", pos: "br" },
  { key: "eliminate", title: "第四象限 · 可以缓缓", en: "不重要不紧急", urgent: false, important: false, accent: "text-ink-soft", bg: "bg-ink/[0.04]", pos: "bl" },
];

export default function QuadrantView({
  tasks,
  onOpen,
  onToggle,
  onMove,
  onClassify,
  classifying,
  classifyMsg,
}: Props) {
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  const [draggingId, setDraggingId] = useState<number | null>(null);

  const pending = tasks.filter((t) => !t.done);
  const unclassified = pending.filter((t) => t.urgent === null || t.important === null);

  function renderCell(q: Quadrant) {
    const items = pending.filter(
      (t) => t.urgent !== null && t.important !== null && !!t.urgent === q.urgent && !!t.important === q.important
    );
    return (
      <div
        key={q.key}
        onDragOver={(e) => {
          e.preventDefault();
          e.dataTransfer.dropEffect = "move";
          setDropTarget(q.key);
        }}
        onDragLeave={() => setDropTarget((cur) => (cur === q.key ? null : cur))}
        onDrop={(e) => {
          e.preventDefault();
          setDropTarget(null);
          const id = Number(e.dataTransfer.getData("text/task-id"));
          const t = tasks.find((x) => x.id === id);
          if (t) onMove(t, q.urgent, q.important);
        }}
        className={`p-3 md:p-5 min-h-[180px] md:min-h-[240px] transition-colors ${
          dropTarget === q.key ? q.bg : ""
        }`}
      >
        <div className={`flex items-baseline gap-2 mb-3 ${q.pos === "tr" || q.pos === "br" ? "md:justify-end" : ""}`}>
          <span className={`text-sm font-semibold ${q.accent}`}>{q.title}</span>
          <span className="text-[11px] text-ink-soft tnum">{items.length}</span>
        </div>
        <div className="space-y-2">
          {items.map((t) => (
            <motion.div
              key={t.id}
              layout
              initial={{ opacity: 0, scale: 0.96 }}
              animate={{ opacity: draggingId === t.id ? 0.4 : 1, scale: 1 }}
              transition={{ duration: 0.18 }}
              draggable
              onDragStart={(e) => {
                (e as unknown as React.DragEvent).dataTransfer?.setData("text/task-id", String(t.id));
                setDraggingId(t.id);
              }}
              onDragEnd={() => {
                setDraggingId(null);
                setDropTarget(null);
              }}
              onClick={() => onOpen(t)}
              className="group flex items-center gap-2.5 rounded-xl border border-line bg-card shadow-card px-3 py-2.5 cursor-grab active:cursor-grabbing hover:border-ink/25 transition-colors"
            >
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onToggle(t);
                }}
                aria-label="完成"
                className="shrink-0 w-4 h-4 rounded-full border-[1.5px] border-ink-soft/50 hover:border-accent transition-colors"
              />
              <div className="min-w-0 flex-1">
                <div className="text-sm truncate">{t.title}</div>
                {t.dueAt && (
                  <div className="text-[11px] tnum text-ink-soft mt-0.5">{fmtShort(t.dueAt)}</div>
                )}
              </div>
              <span className="text-[10px] text-ink-soft/0 group-hover:text-ink-soft/60 transition-colors">⠿</span>
            </motion.div>
          ))}
          {!items.length && (
            <div className="text-xs text-ink-soft/50 py-8 text-center">拖任务到这里</div>
          )}
        </div>
      </div>
    );
  }

  const get = (key: string) => QUADRANTS.find((q) => q.key === key)!;

  return (
    <div>
      <header className="flex flex-wrap items-end justify-between gap-4 mb-8">
        <div>
          <div className="text-[10px] uppercase tracking-[0.2em] text-ink-soft mb-2">
            Eisenhower Matrix
          </div>
          <h1 className="font-display text-[38px] md:text-[44px] leading-none tracking-tight">
            四象限<span className="text-accent">.</span>
          </h1>
          <p className="text-sm text-ink-soft mt-2">
            越靠上越重要，越靠右越紧急，拖动卡片即可调整
          </p>
        </div>
        <div className="flex items-center gap-3">
          {classifyMsg && <span className="text-xs text-ink-soft">{classifyMsg}</span>}
          <button
            onClick={onClassify}
            disabled={classifying}
            className="px-4 py-2 rounded-xl bg-ink text-paper text-sm hover:bg-ink/85 transition disabled:opacity-50"
          >
            {classifying ? "AI 分类中…" : unclassified.length ? `AI 分类（${unclassified.length} 条待分）` : "AI 重新分类"}
          </button>
        </div>
      </header>

      {/* 坐标平面：Y 轴（重要性）在左，X 轴（紧急性）在下 */}
      <div className="flex">
        {/* Y 轴 */}
        <div className="relative w-8 md:w-12 shrink-0">
          <div className="absolute inset-y-0 right-2 md:right-4 flex flex-col items-center">
            <span className="text-[11px] md:text-xs text-ink-soft tracking-widest [writing-mode:vertical-rl] mb-2">
              重要性 ↑
            </span>
            <div className="flex-1 w-px bg-ink/25" />
          </div>
        </div>

        {/* 平面主体 */}
        <div className="flex-1 min-w-0">
          <div className="grid grid-cols-2">
            {/* 左上：第二象限 计划做 / 右上：第一象限 马上做 */}
            <div className="border-r border-b border-ink/15">{renderCell(get("plan"))}</div>
            <div className="border-b border-ink/15">{renderCell(get("do"))}</div>
            {/* 左下：第四象限 可以缓缓 / 右下：第三象限 快速处理 */}
            <div className="border-r border-ink/15">{renderCell(get("eliminate"))}</div>
            <div>{renderCell(get("delegate"))}</div>
          </div>
          {/* X 轴 */}
          <div className="flex items-center gap-3 mt-3">
            <span className="text-[11px] md:text-xs text-ink-soft whitespace-nowrap">不紧急</span>
            <svg className="flex-1 h-3 text-ink/40" preserveAspectRatio="none" viewBox="0 0 100 12" aria-hidden>
              <line x1="0" y1="6" x2="96" y2="6" stroke="currentColor" strokeWidth="1" vector-effect="non-scaling-stroke" />
              <path d="M94 1 L100 6 L94 11 Z" fill="currentColor" />
            </svg>
            <span className="text-[11px] md:text-xs text-ink-soft whitespace-nowrap">紧急性</span>
          </div>
        </div>
      </div>

      {unclassified.length > 0 && (
        <section className="mt-6 rounded-2xl border border-dashed border-line p-4">
          <div className="text-xs text-ink-soft mb-3">
            未分类（{unclassified.length}）— 点「AI 分类」或手动拖入象限
          </div>
          <div className="flex flex-wrap gap-2">
            {unclassified.map((t) => (
              <div
                key={t.id}
                draggable
                onDragStart={(e) => {
                  e.dataTransfer.setData("text/task-id", String(t.id));
                  setDraggingId(t.id);
                }}
                onDragEnd={() => setDraggingId(null)}
                onClick={() => onOpen(t)}
                className="text-xs rounded-lg border border-line bg-card px-3 py-2 cursor-grab active:cursor-grabbing hover:border-ink/25 transition-colors"
              >
                {t.title}
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
