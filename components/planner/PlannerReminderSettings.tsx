"use client";

import { useRef, useState, type FormEvent } from "react";
import { plannerError, plannerRequest, PlannerResponseError, type PlannerSettings } from "@/lib/planner/client";
import { field, primaryButton, quietButton } from "./controls";

export default function PlannerReminderSettings() {
  const [open, setOpen] = useState(false);
  const [base, setBase] = useState<PlannerSettings>();
  const [enabled, setEnabled] = useState(false);
  const [time, setTime] = useState("21:30");
  const [pending, setPending] = useState<Record<string, unknown>>();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const received = useRef(0);
  const lock = useRef(false);

  function update(settings: PlannerSettings, keepEdits = false) {
    received.current = Date.now();
    setBase(settings);
    if (!keepEdits) {
      setEnabled(settings.enabled);
      setTime(settings.time);
    }
  }

  async function read() {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError("");
    try {
      update(await plannerRequest<PlannerSettings>("/settings"));
    } catch (failure) {
      setError(plannerError(failure));
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (lock.current || !base) return;
    const body = pending ?? {
      enabled, time, baseVersion: base.revision, operationId: crypto.randomUUID(),
      issuedAt: base.serverTime + Date.now() - received.current,
    };
    lock.current = true;
    setBusy(true);
    setError("");
    setMessage("");
    setPending(body);
    try {
      update(await plannerRequest<PlannerSettings>("/settings", body, undefined, "PUT"));
      setPending(undefined);
      setMessage("提醒设置已同步");
    } catch (failure) {
      if (failure instanceof PlannerResponseError && !failure.uncertain) {
        setPending(undefined);
        if (failure.settings) {
          update(failure.settings, true);
          setError("另一端已改为" + (failure.settings.enabled ? "开启" : "关闭") + " · " + failure.settings.time + "。请核对后再保存。");
          return;
        }
      }
      setError(plannerError(failure));
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }

  return (
    <section className="rounded-2xl border border-line bg-card shadow-card">
      <button type="button" aria-expanded={open} className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left text-sm font-medium"
        onClick={() => { setOpen(!open); if (!open && !base) void read(); }}>
        提醒设置 <span aria-hidden className="text-ink-soft">{open ? "−" : "+"}</span>
      </button>
      {open && <form className="space-y-3 border-t border-line p-4" onSubmit={(event) => void save(event)}>
        <fieldset disabled={busy || !!pending || !base} className="space-y-3">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" className="accent-accent" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} /> Android 晚间提醒
          </label>
          <label className="block text-sm">提醒时间（UTC+8）
            <input type="time" required className={field + " mt-1"} value={time} onChange={(event) => setTime(event.target.value)} />
          </label>
        </fieldset>
        {error && <p role="alert" className="text-sm text-danger">{error}</p>}
        {message && <p role="status" className="text-sm text-ink-soft">{message}</p>}
        <div className="flex flex-wrap gap-2">
          <button className={primaryButton} disabled={busy || !base} type="submit">{pending ? "重试原操作" : "保存提醒"}</button>
          <button className={quietButton} disabled={busy || !!pending} type="button" onClick={() => void read()}>刷新设置</button>
        </div>
      </form>}
    </section>
  );
}
