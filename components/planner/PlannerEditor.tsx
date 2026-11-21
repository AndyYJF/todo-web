"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import type { PlanItem } from "@/lib/planner/domain";
import type { Task } from "@/lib/types";
import { plannerError, plannerRequest, PlannerResponseError } from "@/lib/planner/client";
import { field, primaryButton, quietButton } from "./controls";

type Fields = Pick<PlanItem, "title" | "note" | "startTime" | "endTime" | "todoId">;
export type PlanDraft = { date: string; existing?: PlanItem; startTime?: string; endTime?: string };
export type StoredPlanDraft = {
  draft: PlanDraft;
  base?: PlanItem;
  input: Fields;
  target: string;
  pending: Record<string, unknown> | null;
  conflict: PlanItem | null;
};
type Props = { draft: PlanDraft; saved?: StoredPlanDraft; minDate: string; tasks: Task[]; issuedAt: () => number;
  onClose: (saved?: StoredPlanDraft) => void; onSaved: (date: string) => void };
const draftKey = "todo-planner-work-draft";

export function readPlannerDraft(): StoredPlanDraft | undefined {
  try { return JSON.parse(sessionStorage.getItem(draftKey) ?? "null") ?? undefined; }
  catch { return undefined; }
}

export function rememberPlannerDraft(saved?: StoredPlanDraft) {
  try {
    if (saved) sessionStorage.setItem(draftKey, JSON.stringify(saved));
    else sessionStorage.removeItem(draftKey);
  } catch { /* If session storage is unavailable, the mounted view holds the draft. */ }
}

function values(item: PlanItem): Fields {
  const { title, note, startTime, endTime, todoId } = item;
  return { title, note, startTime, endTime, todoId };
}

export default function PlannerEditor({ draft, saved, minDate, tasks, issuedAt, onClose, onSaved }: Props) {
  const [base, setBase] = useState(saved?.base ?? draft.existing);
  const [input, setInput] = useState<Fields>(saved?.input ?? (draft.existing ? values(draft.existing) :
    { title: "", note: "", startTime: draft.startTime ?? null, endTime: draft.endTime ?? null, todoId: null }));
  const [target, setTarget] = useState(saved?.target ?? draft.date);
  const [error, setError] = useState("");
  const [conflict, setConflict] = useState(saved?.conflict ?? null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [pending, setPending] = useState(saved?.pending ?? null);
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const titleField = useRef<HTMLInputElement>(null);

  useEffect(() => {
    rememberPlannerDraft({ draft, base, input, target, pending, conflict });
  }, [draft, base, input, target, pending, conflict]);

  useEffect(() => { titleField.current?.focus(); }, []);

  function change<K extends keyof Fields>(key: K, value: Fields[K]) {
    setInput((current) => ({ ...current, [key]: value }));
  }
  function changedFrom(item: PlanItem) {
    return Object.fromEntries(Object.entries(input).filter(([key, value]) => value !== item[key as keyof Fields]));
  }
  async function submit(event?: FormEvent, remove = false) {
    event?.preventDefault();
    if (lock.current || conflict) return;
    const fields = base ? changedFrom(base) : input;
    const action = remove ? "delete" : !base ? "create" : target !== draft.date ? "move" : "edit";
    if (!pending && action === "edit" && !Object.keys(fields).length) { onClose(); return; }
    const body = pending ?? {
      action, operationId: crypto.randomUUID(), issuedAt: issuedAt(),
      date: base ? draft.date : target,
      ...(base ? { itemId: base.id, baseVersion: base.version } : {}),
      ...(action === "move" ? { targetDate: target } : {}),
      ...(action === "create" || action === "edit" || (action === "move" && Object.keys(fields).length) ? { fields } : {}),
    };
    lock.current = true;
    setBusy(true);
    setError("");
    setPending(body);
    rememberPlannerDraft({ draft, base, input, target, pending: body, conflict });
    try {
      await plannerRequest("", body);
      rememberPlannerDraft();
      onSaved(body.action === "move" ? String(body.targetDate) : String(body.date));
    } catch (error) {
      if (error instanceof PlannerResponseError && !error.uncertain) {
        setPending(null);
        if (error.code === "item_conflict" && error.current) setConflict(error.current);
      }
      setError(plannerError(error));
    } finally { lock.current = false; setBusy(false); }
  }

  return (
    <form className="space-y-3 rounded-2xl border border-accent/30 bg-card p-4 shadow-card" onSubmit={(event) => void submit(event)}>
      <h3 className="font-medium">{base ? "编辑安排" : "添加安排"}</h3>
      <fieldset disabled={busy || !!pending} className="space-y-3">
        {!base && tasks.some((task) => !task.done) && <label className="block text-sm">从待办选择
          <select className={field + " mt-1"} value={input.todoId ?? ""}
            onChange={(event) => {
              const task = tasks.find((item) => item.id === Number(event.target.value));
              setInput((current) => ({ ...current, todoId: task?.id ?? null, title: task?.title ?? current.title }));
            }}>
            <option value="">手动添加</option>
            {tasks.filter((task) => !task.done).map((task) => <option key={task.id} value={task.id}>{task.title}</option>)}
          </select>
        </label>}
        <label className="block text-sm">标题
          <input ref={titleField} required maxLength={160} className={field + " mt-1"} value={input.title}
            onChange={(event) => change("title", event.target.value)} />
        </label>
        <label className="block text-sm">日期
          <input required type="date" min={minDate} max="2099-12-31" className={field + " mt-1"} value={target}
            onChange={(event) => setTarget(event.target.value)} />
        </label>
        <div className="grid grid-cols-2 gap-2">
          <label className="min-w-0 text-sm">开始
            <input type="time" className={field + " mt-1"} required={!!input.endTime} value={input.startTime ?? ""}
              onChange={(event) => change("startTime", event.target.value || null)} />
          </label>
          <label className="min-w-0 text-sm">结束
            <input type="time" className={field + " mt-1"} required={!!input.startTime} value={input.endTime ?? ""}
              onChange={(event) => change("endTime", event.target.value || null)} />
          </label>
        </div>
        <label className="block text-sm">备注
          <textarea className={field + " mt-1"} rows={2} value={input.note}
            onChange={(event) => change("note", event.target.value)} />
        </label>
      </fieldset>
      {error && <p role="alert" className="break-words text-sm text-danger">{error}</p>}
      {conflict && <div className="space-y-2 rounded-lg bg-warn-soft p-3 text-sm text-warn">
        <p>服务器版本：{conflict.title} {conflict.startTime ?? "待安排"} {conflict.endTime ?? ""}</p>
        {conflict.note && <p className="break-words">{conflict.note}</p>}
        <button type="button" className={quietButton} onClick={() => {
          if (base) setInput({ ...values(conflict), ...changedFrom(base) });
          setBase(conflict); setConflict(null); setError("");
        }}>按最新版本继续编辑</button>
      </div>}
      <div className="flex flex-wrap gap-2">
        {pending ? <button type="button" className={primaryButton} disabled={busy} onClick={() => void submit()}>
          {busy ? "保存中…" : "用原操作重试"}
        </button> : <button type="submit" className={primaryButton} disabled={busy || !!conflict}>
          {base && target !== draft.date ? "移动安排" : "保存安排"}
        </button>}
        <button type="button" className={quietButton} disabled={busy}
          onClick={() => onClose({ draft, base, input, target, pending, conflict })}>关闭</button>
        {!pending && <button type="button" className={quietButton} disabled={busy} onClick={() => onClose()}>放弃草稿</button>}
        {base && !pending && <button type="button" className="px-2 text-sm text-danger" disabled={busy || !!conflict}
          onClick={() => { if (confirmDelete) void submit(undefined, true); else setConfirmDelete(true); }}>
          {confirmDelete ? "确认删除" : "删除"}
        </button>}
      </div>
    </form>
  );
}
