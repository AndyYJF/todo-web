"use client";

import { useRef, useState } from "react";
import { MAX_PLANNER_IMPORT, plannerError, plannerRequest, PlannerResponseError, type ImportPreview } from "@/lib/planner/client";
import { field, primaryButton, quietButton } from "./controls";

export default function PlannerImport({ onImported }: { onImported: (message: string) => void }) {
  const [open, setOpen] = useState(false);
  const [source, setSource] = useState("");
  const [filename, setFilename] = useState("");
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [pending, setPending] = useState<Record<string, unknown> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const lock = useRef(false);
  const fileInput = useRef<HTMLInputElement>(null);

  async function run(kind: "preview" | "commit") {
    if (lock.current || !source.trim()) return;
    lock.current = true;
    setBusy(true);
    setError("");
    try {
      if (new TextEncoder().encode(source).length > MAX_PLANNER_IMPORT) throw new Error("课表文件最大 1 MiB");
      if (kind === "preview") {
        setPreview(null);
        setPreview(await plannerRequest<ImportPreview>("/timetable", { action: "preview", ics: source }));
      } else if (preview) {
        const body = pending ?? {
          action: "commit", ics: source, checksum: preview.checksum, effectiveFrom: preview.effectiveFrom,
          baseVersion: preview.baseVersion, issuedAt: preview.serverTime, operationId: crypto.randomUUID(),
        };
        setPending(body);
        const result = await plannerRequest<{ added: number; updated: number; removed: number }>("/timetable", body);
        setPending(null);
        setPreview(null);
        setSource("");
        setFilename("");
        setOpen(false);
        onImported("课表已同步。新增 " + result.added + "，更新 " + result.updated + "，移除 " + result.removed + "。");
      }
    } catch (error) {
      if (kind === "commit" && error instanceof PlannerResponseError && !error.uncertain) {
        setPending(null);
        if (error.status === 409) setPreview(null);
      }
      setError(plannerError(error));
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }

  async function choose(file: File | undefined) {
    if (!file || lock.current) return;
    lock.current = true;
    setBusy(true);
    setError("");
    try {
      if (!file.name.toLowerCase().endsWith(".ics")) throw new Error("请选择 .ics 文件");
      if (file.size > MAX_PLANNER_IMPORT) throw new Error("课表文件最大 1 MiB");
      const text = new TextDecoder("utf-8", { fatal: true }).decode(await file.arrayBuffer());
      setSource(text);
      setFilename(file.name);
      setPreview(null);
    } catch (error) {
      setError(plannerError(error));
    } finally {
      if (fileInput.current) fileInput.current.value = "";
      setBusy(false);
      lock.current = false;
    }
  }

  return (
    <section className="rounded-2xl border border-line bg-card shadow-card">
      <button type="button" aria-expanded={open} onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left text-sm font-medium">
        导入课表 <span className="text-ink-soft" aria-hidden>{open ? "−" : "+"}</span>
      </button>
      {open && <div className="space-y-3 border-t border-line px-4 py-4">
        <input ref={fileInput} type="file" accept=".ics,text/calendar" hidden disabled={busy || !!pending} onChange={(event) => void choose(event.target.files?.[0])} />
        <button type="button" className={quietButton} disabled={busy || !!pending} onClick={() => fileInput.current?.click()}>
          选择 .ics 文件
        </button>
        {filename && <div className="break-all text-xs text-ink-soft">{filename}</div>}
        <label className="block text-sm">或粘贴 iCalendar 文本
          <textarea rows={3} className={field + " mt-1 font-mono"} value={source} disabled={busy || !!pending}
            onChange={(event) => { setSource(event.target.value); setFilename(""); setPreview(null); }} />
        </label>
        {error && <p role="alert" className="text-sm text-danger">{error}</p>}
        {preview && <div className="space-y-2 rounded-xl bg-paper p-3 text-sm">
          <p className="tnum">{preview.from} 至 {preview.through}</p>
          <p>解析 {preview.count} 条。新增 {preview.added}，更新 {preview.updated}，移除 {preview.removed}。</p>
          {preview.sample.length > 0 && <ul className="max-h-48 space-y-2 overflow-auto border-t border-line pt-2">
            {preview.sample.map((course) => <li key={course.key}>
              <span className="tnum text-ink-soft">{course.date} {course.startsAt.slice(11, 16)} </span>
              {course.title}{course.location ? " · " + course.location : ""}
            </li>)}
          </ul>}
        </div>}
        <div className="flex flex-wrap gap-2">
          <button type="button" className={quietButton} disabled={!source.trim() || busy || !!pending} onClick={() => void run("preview")}>
            预览课表
          </button>
          {preview && <button type="button" className={primaryButton} disabled={busy || preview.through < preview.effectiveFrom} onClick={() => void run("commit")}>
            {busy ? "正在处理…" : pending ? "用原操作重试" : "确认导入"}
          </button>}
        </div>
      </div>}
    </section>
  );
}
