"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion } from "motion/react";

const WEEK = ["一", "二", "三", "四", "五", "六", "日"];

const pad = (n: number) => String(n).padStart(2, "0");
const fmt = (d: Date) =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;

function parse(v: string | null): Date | null {
  if (!v) return null;
  const d = new Date(v.replace(" ", "T"));
  return isNaN(d.getTime()) ? null : d;
}

/** 小日历式日期时间选择器。value 格式 "YYYY-MM-DD HH:mm"，null = 未设置 */
export default function DateTimePicker({
  value,
  onChange,
  placeholder = "选择时间",
  compact = false,
}: {
  value: string | null;
  onChange: (v: string | null) => void;
  placeholder?: string;
  compact?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const cur = parse(value);
  const [view, setView] = useState<Date>(cur ?? new Date());
  const ref = useRef<HTMLDivElement>(null);
  const popRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState({ top: 0, left: 0 });

  // 点击外部关闭（弹层 portal 到 body，需同时检查两处）
  useEffect(() => {
    if (!open) return;
    function onDoc(e: MouseEvent) {
      const t = e.target as Node;
      if (
        ref.current &&
        !ref.current.contains(t) &&
        popRef.current &&
        !popRef.current.contains(t)
      )
        setOpen(false);
    }
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, [open]);

  // 打开时：日历定位到已选月份 + 计算 fixed 位置（不被父容器 overflow 裁剪）
  useEffect(() => {
    if (!open) return;
    setView(cur ?? new Date());
    const rect = ref.current?.getBoundingClientRect();
    if (rect) {
      const W = 264;
      setPos({
        top: rect.bottom + 8,
        left: Math.max(8, Math.min(rect.right - W, window.innerWidth - W - 8)),
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const y = view.getFullYear();
  const m = view.getMonth();
  const offset = (new Date(y, m, 1).getDay() + 6) % 7; // 周一开头
  const dim = new Date(y, m + 1, 0).getDate();
  const cells: (number | null)[] = [
    ...Array<null>(offset).fill(null),
    ...Array.from({ length: dim }, (_, i) => i + 1),
  ];
  while (cells.length % 7) cells.push(null);

  const today = new Date();
  const isToday = (d: number) =>
    d === today.getDate() &&
    m === today.getMonth() &&
    y === today.getFullYear();
  const isSel = (d: number) =>
    !!cur &&
    d === cur.getDate() &&
    m === cur.getMonth() &&
    y === cur.getFullYear();

  const curTime = cur ? `${pad(cur.getHours())}:${pad(cur.getMinutes())}` : "18:00";

  function pickDay(day: number) {
    const [hh, mm] = curTime.split(":").map(Number);
    onChange(fmt(new Date(y, m, day, hh, mm)));
  }

  function setTime(t: string) {
    if (!/^\d{2}:\d{2}$/.test(t)) return;
    const base = cur ?? new Date(y, m, today.getDate());
    const [hh, mm] = t.split(":").map(Number);
    onChange(fmt(new Date(base.getFullYear(), base.getMonth(), base.getDate(), hh, mm)));
  }

  function quick(daysAhead: number) {
    const d = new Date();
    d.setDate(d.getDate() + daysAhead);
    const [hh, mm] = curTime.split(":").map(Number);
    d.setHours(hh, mm, 0, 0);
    onChange(fmt(d));
  }

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className={
          compact
            ? "flex items-center gap-1 bg-paper border border-line rounded-lg px-2.5 py-1.5 text-xs text-ink-soft tnum cursor-pointer hover:border-ink/30 transition-colors whitespace-nowrap"
            : "w-full bg-paper border border-line rounded-xl px-3.5 py-2.5 text-sm tnum text-left hover:border-ink/30 transition-colors " +
              (value ? "" : "text-ink-soft/60")
        }
      >
        {value ? (
          compact ? (
            `${Number(value.slice(5, 7))}/${Number(value.slice(8, 10))} ${value.slice(11)}`
          ) : (
            value
          )
        ) : (
          placeholder
        )}
        {value && (
          <span
            role="button"
            aria-label="清除"
            onClick={(e) => {
              e.stopPropagation();
              onChange(null);
            }}
            className="ml-1 text-ink-soft/60 hover:text-danger transition-colors"
          >
            ×
          </span>
        )}
      </button>

      {open &&
        createPortal(
          <AnimatePresence>
          {open && (
            <motion.div
              ref={popRef}
              initial={{ opacity: 0, y: 6, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 6, scale: 0.97 }}
              transition={{ duration: 0.13, ease: "easeOut" }}
              style={{ position: "fixed", top: pos.top, left: pos.left }}
              className="z-[100] w-[264px] bg-card border border-line rounded-2xl shadow-lift p-3"
            >
            {/* 月份导航 */}
            <div className="flex items-center justify-between mb-2 px-1">
              <button
                onClick={() => setView(new Date(y, m - 1, 1))}
                className="w-7 h-7 rounded-lg hover:bg-paper text-ink-soft grid place-items-center"
                aria-label="上个月"
              >
                ‹
              </button>
              <div className="text-[13px] font-medium tnum">
                {y} 年 {m + 1} 月
              </div>
              <button
                onClick={() => setView(new Date(y, m + 1, 1))}
                className="w-7 h-7 rounded-lg hover:bg-paper text-ink-soft grid place-items-center"
                aria-label="下个月"
              >
                ›
              </button>
            </div>

            {/* 星期头 */}
            <div className="grid grid-cols-7 text-center text-[10px] text-ink-soft/70 mb-1">
              {WEEK.map((w) => (
                <div key={w}>{w}</div>
              ))}
            </div>

            {/* 日期网格 */}
            <div className="grid grid-cols-7 gap-0.5">
              {cells.map((d, i) =>
                d === null ? (
                  <div key={i} />
                ) : (
                  <button
                    key={i}
                    onClick={() => pickDay(d)}
                    className={`h-8 rounded-lg text-xs tnum transition-colors ${
                      isSel(d)
                        ? "bg-ink text-paper font-medium"
                        : isToday(d)
                          ? "text-accent font-semibold hover:bg-accent-soft"
                          : "hover:bg-paper"
                    }`}
                  >
                    {d}
                  </button>
                )
              )}
            </div>

            {/* 快捷键 + 时间 */}
            <div className="mt-3 pt-3 border-t border-line space-y-2">
              <div className="flex gap-1.5">
                {[
                  ["今天", 0],
                  ["明天", 1],
                  ["后天", 2],
                  ["下周", 7],
                ].map(([label, n]) => (
                  <button
                    key={label as string}
                    onClick={() => quick(n as number)}
                    className="flex-1 py-1.5 rounded-lg bg-paper text-[11px] text-ink-soft hover:text-ink hover:bg-line/60 transition-colors"
                  >
                    {label}
                  </button>
                ))}
              </div>
              <div className="flex items-center gap-2">
                <input
                  type="time"
                  value={curTime}
                  onChange={(e) => setTime(e.target.value)}
                  className="flex-1 bg-paper border border-line rounded-lg px-2.5 py-1.5 text-xs tnum outline-none focus:border-ink/40"
                />
                <button
                  onClick={() => setOpen(false)}
                  className="bg-ink text-paper rounded-lg px-4 py-1.5 text-xs font-medium hover:bg-black transition-colors"
                >
                  完成
                </button>
              </div>
            </div>
          </motion.div>
        )}
          </AnimatePresence>,
          document.body
        )}
    </div>
  );
}
