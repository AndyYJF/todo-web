"use client";

import { useEffect, useRef, useState } from "react";
import { plannerError, plannerRequest, type PlanHistory } from "@/lib/planner/client";
import { quietButton } from "./controls";

function size(bytes: number) {
  return bytes < 1_000_000 ? (bytes / 1000).toLocaleString("zh-CN", { maximumFractionDigits: 1 }) + " KB"
    : (bytes / 1_000_000).toLocaleString("zh-CN", { maximumFractionDigits: 1 }) + " MB";
}

export default function PlannerHistory({ onOpen }: { onOpen: (date: string) => void }) {
  const [page, setPage] = useState<PlanHistory>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const request = useRef<AbortController | null>(null);

  async function read(before?: string) {
    request.current?.abort();
    const current = new AbortController();
    request.current = current;
    try {
      const page = await plannerRequest<PlanHistory>(
        "?view=history" + (before ? "&before=" + encodeURIComponent(before) : ""), undefined, current.signal,
      );
      if (current.signal.aborted) return;
      setPage((previous) => ({
        ...page,
        items: before && previous
          ? [...previous.items.filter((item) => page.earliestDate && item.date >= page.earliestDate), ...page.items]
          : page.items,
      }));
      setError("");
    } catch (error) {
      if (!current.signal.aborted) setError(plannerError(error));
    } finally {
      if (!current.signal.aborted) setBusy(false);
    }
  }

  useEffect(() => {
    const initial = window.setTimeout(() => void read(), 0);
    return () => {
      window.clearTimeout(initial);
      request.current?.abort();
    };
  }, []);

  function refresh(before?: string) {
    setBusy(true);
    void read(before);
  }

  return (
    <section aria-label="历史记录" className="rounded-2xl border border-line bg-card p-4 shadow-card">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-medium">历史记录</h2>
          {page && <p className="mt-1 text-sm text-ink-soft">
            {size(page.bytes)} / {size(page.limitBytes)}{page.earliestDate ? " · 最早 " + page.earliestDate : ""}
          </p>}
        </div>
        <button type="button" className={quietButton} disabled={busy} onClick={() => refresh()}>刷新历史</button>
      </div>
      {error && <p role="alert" className="mt-3 text-sm text-danger">{error}</p>}
      {busy && !page && <p role="status" className="mt-3 text-sm text-ink-soft">正在读取历史…</p>}
      {!busy && page?.items.length === 0 && <p className="mt-3 text-sm text-ink-soft">还没有归档的日计划。</p>}
      {page && <ul className="mt-3 divide-y divide-line">
        {page.items.map((entry) => <li key={entry.date}>
          <button type="button" className="flex w-full flex-wrap justify-between gap-3 rounded-lg px-2 py-3 text-left text-sm hover:bg-paper"
            onClick={() => onOpen(entry.date)}>
            <span className="tnum font-medium">{entry.date}</span>
            <span className="text-ink-soft">已完成 {entry.doneCount} / {entry.itemCount}</span>
          </button>
        </li>)}
      </ul>}
      {page?.nextBefore && <button type="button" className={quietButton + " mt-3"} disabled={busy}
        onClick={() => refresh(page.nextBefore!)}>加载更早记录</button>}
    </section>
  );
}
