"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { IconCalendar, IconClock } from "./icons";
import PlannerEditor, { planFields, readPlannerDraft, rememberPlannerDraft, type PlanDraft, type StoredPlanDraft } from "./planner/PlannerEditor";
import PlannerImport from "./planner/PlannerImport";
import PlannerReminderSettings from "./planner/PlannerReminderSettings";
import PlannerHistory from "./planner/PlannerHistory";
import type { PlanItem } from "@/lib/planner/domain";
import { primaryButton, quietButton, field } from "./planner/controls";
import { businessDate, dateEpoch, DAY_MS } from "@/lib/planner/dates";
import { formatMinute, plannerError, plannerRequest, planStatusLabel, PlannerResponseError, timeline, type PlanDay, type SchoolWeek } from "@/lib/planner/client";
import type { Task } from "@/lib/types";

const nextDate = (date: string, offset = 1) =>
  new Date(dateEpoch(date) + offset * DAY_MS).toISOString().slice(0, 10);
const dateTitle = (date: string) =>
  new Intl.DateTimeFormat("zh-CN", { timeZone: "UTC", month: "long", day: "numeric", weekday: "long" })
    .format(new Date(dateEpoch(date)));

export default function PlannerView({ tasks }: { tasks: Task[] }) {
  const [history, setHistory] = useState(false);
  const [hideDone, setHideDone] = useState(false);
  const [marking, setMarking] = useState(false);
  const markLock = useRef(false);
  const [date, setDate] = useState(() => nextDate(businessDate()));
  const [snapshot, setSnapshot] = useState<PlanDay>();
  const [academic, setAcademic] = useState<{ date: string; week: SchoolWeek["current"] }>();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [draft, setDraft] = useState<PlanDraft | null>(null);
  const [saved, setSaved] = useState<StoredPlanDraft>();
  const dayRequest = useRef<AbortController | null>(null);
  const initialRead = useRef(true);
  const clock = useRef({ server: 0, received: 0 });

  const readDay = useCallback(async (target: string) => {
    dayRequest.current?.abort();
    const request = new AbortController();
    dayRequest.current = request;
    try {
      if (initialRead.current) {
        const current = await plannerRequest<PlanDay>("", undefined, request.signal);
        if (request.signal.aborted) return;
        initialRead.current = false;
        const tomorrow = nextDate(current.today);
        if (tomorrow !== target) {
          setSnapshot(current);
          setDate(tomorrow);
          return;
        }
      }
      const next = await plannerRequest<PlanDay>("?date=" + encodeURIComponent(target), undefined, request.signal);
      if (request.signal.aborted || next.date !== target) return;
      clock.current = { server: next.serverTime, received: Date.now() };
      setSnapshot((current) => current?.date === next.date && current.revision > next.revision ? current : next);
      setError("");
    } catch (error) {
      if (!request.signal.aborted) {
        if (error instanceof PlannerResponseError && error.status === 410) {
          setSnapshot((current) => current?.date === target ? undefined : current);
        }
        setError(plannerError(error));
      }
    }
  }, []);

  useEffect(() => {
    const restore = window.setTimeout(() => setSaved(readPlannerDraft()), 0);
    return () => window.clearTimeout(restore);
  }, []);

  useEffect(() => {
    if (history) return;
    const initial = window.setTimeout(() => void readDay(date), 0);
    const refreshVisible = () => { if (document.visibilityState === "visible") void readDay(date); };
    const interval = window.setInterval(refreshVisible, 30_000);
    window.addEventListener("focus", refreshVisible);
    document.addEventListener("visibilitychange", refreshVisible);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(interval);
      window.removeEventListener("focus", refreshVisible);
      document.removeEventListener("visibilitychange", refreshVisible);
      dayRequest.current?.abort();
    };
  }, [date, history, readDay]);

  useEffect(() => {
    const request = new AbortController();
    void plannerRequest<SchoolWeek>("/academic-calendar?date=" + date, undefined, request.signal)
      .then((result) => { if (!request.signal.aborted) setAcademic({ date, week: result.current }); })
      .catch(() => {});
    return () => request.abort();
  }, [date]);

  const day = snapshot?.date === date ? snapshot : undefined;
  const today = snapshot?.today ?? businessDate();
  const earliest = snapshot?.openFrom ?? today;
  const tomorrow = nextDate(today);
  const week = academic?.date === date ? academic?.week : null;
  const canEdit = !!day && !day.archived && date >= day.openFrom;
  const canMark = canEdit && date <= today;
  const itemControlsDisabled = !!draft || !!saved || marking;
  const groups = day ? timeline(day) : [];
  const free = groups.filter((entry) => entry.kind === "gap");
  const done = day?.items.filter((item) => item.status === "done").length ?? 0;
  const unfinished = day?.items.filter((item) => item.status === "unfinished").length ?? 0;
  const unscheduled = day?.items.filter((item) => item.startTime === null && (!hideDone || item.status !== "done")) ?? [];
  const issuedAt = useCallback(() => {
    const local = Date.now();
    const { server, received } = clock.current;
    return server ? server + local - received : local;
  }, []);

  function openDraft(next: PlanDraft) {
    const selected = saved?.draft ?? next;
    if (selected.date !== date || history) chooseDate(selected.date);
    setMessage("");
    setDraft(selected);
  }
  function chooseDate(target: string) {
    initialRead.current = false;
    setHistory(false);
    setError("");
    setMessage("");
    setHideDone(false);
    setDate(target);
  }
  function closeDraft(next?: StoredPlanDraft) {
    rememberPlannerDraft(next);
    setSaved(next);
    setDraft(null);
    void readDay(date);
  }

  function finished(target: string) {
    setDraft(null);
    setSaved(undefined);
    setMessage("安排已保存");
    if (date === target) void readDay(date);
    else setDate(target);
  }

  async function mark(item: PlanItem) {
    if (!canMark || itemControlsDisabled || markLock.current) return;
    const status = item.status === "done" ? "pending" : "done";
    const pending = { action: "edit", date, itemId: item.id, baseVersion: item.version,
      fields: { status }, operationId: crypto.randomUUID(), issuedAt: issuedAt() };
    const attempt: StoredPlanDraft = {
      draft: { date, existing: item }, base: item, target: date,
      input: { ...planFields(item), status }, pending, conflict: null,
    };
    markLock.current = true;
    setMarking(true);
    setMessage("");
    rememberPlannerDraft(attempt);
    try {
      await plannerRequest("", pending);
      rememberPlannerDraft();
      setMessage("状态已同步");
      void readDay(date);
    } catch (error) {
      const response = error instanceof PlannerResponseError ? error : null;
      const next = { ...attempt,
        pending: response && !response.uncertain ? null : pending,
        conflict: response?.code === "item_conflict" ? response.current ?? null : null,
        canCorrectHistory: response?.status === 409 && response.code === "history_read_only",
        error: plannerError(error),
      };
      rememberPlannerDraft(next);
      setSaved(next);
      setDraft(next.draft);
    } finally {
      markLock.current = false;
      setMarking(false);
    }
  }

  function itemActions(item: PlanItem) {
    const archived = day?.archived === true;
    const label = item.status === "done" ? "撤销完成" : "勾选完成";
    const edit = archived ? "补记" : "编辑";
    return <div className="flex flex-wrap gap-2">
      {canMark && <button type="button" className={quietButton} disabled={itemControlsDisabled}
        aria-label={label + " " + item.title} aria-pressed={item.status === "done"}
        onClick={() => void mark(item)}>{item.status === "done" ? "撤销" : "完成"}</button>}
      {(canEdit || archived) && <button type="button" className={quietButton} disabled={itemControlsDisabled}
        aria-label={edit + " " + item.title}
        onClick={() => openDraft({ date, existing: item, correctHistory: archived })}>{edit}</button>}
    </div>;
  }

  function itemResult(item: PlanItem) {
    return <div className="mt-1 space-y-1 text-xs text-ink-soft">
      {(date <= today || item.status !== "pending") && <p className={item.status === "unfinished" ? "text-warn" : undefined}>{planStatusLabel[item.status]}</p>}
      {item.note && <p className="whitespace-pre-wrap break-words">{item.note}</p>}
    </div>;
  }

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-4xl tracking-tight md:text-5xl">规划明天<span className="text-accent">.</span></h1>
          <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-ink-soft">
            {!history && <span className="tnum">{dateTitle(date)}</span>}
            {!history && week && <span>{week.phase === "exam" ? "考试周" : week.phase === "practice" ? "实践周" : "教学周"} · 第 {week.week} 周{week.source === "bugaoshan" ? "（参考）" : ""}</span>}
          </div>
        </div>
        {(saved || (!history && canEdit)) && <button className={primaryButton} disabled={!!draft || marking}
          onClick={() => openDraft({ date })}>{saved ? "继续规划草稿" : "＋ 添加安排"}</button>}
      </header>
      <div className="flex flex-wrap items-center gap-2">
        {earliest < today && <button className={quietButton} disabled={!!draft || marking} aria-pressed={!history && date === earliest} onClick={() => chooseDate(earliest)}>昨天待补记</button>}
        <button className={!history && date === today ? primaryButton : quietButton} aria-pressed={!history && date === today} disabled={!!draft || marking} onClick={() => chooseDate(today)}>今天</button>
        <button className={!history && date === tomorrow ? primaryButton : quietButton} aria-pressed={!history && date === tomorrow} disabled={!!draft || marking} onClick={() => chooseDate(tomorrow)}>明天</button>
        <button className={history || day?.archived ? primaryButton : quietButton} aria-pressed={history || day?.archived === true}
          disabled={!!draft || marking} onClick={() => setHistory(true)}>历史</button>
        {!history && !day?.archived && <input aria-label="选择规划日期" className={field + " !w-auto"} type="date" value={date} min={earliest} max="2099-12-31"
          disabled={!!draft || marking} onChange={(event) => { if (event.target.value && event.target.validity.valid) chooseDate(event.target.value); }} />}
        {!history && <button className={quietButton + " ml-auto"} onClick={() => void readDay(date)}>刷新</button>}
      </div>
      {history && <PlannerHistory onOpen={chooseDate} />}
      {!history && error && <p role="alert" className="rounded-lg bg-danger-soft px-3 py-2 text-sm text-danger">{error}</p>}
      {!history && message && <p role="status" className="rounded-lg bg-accent-soft px-3 py-2 text-sm text-accent-deep">{message}</p>}
      {!history && !day && !error && <p role="status" className="text-sm text-ink-soft">正在读取当天的安排…</p>}
      {!history && (day || draft) && <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_21rem]">
        <section className="min-w-0 space-y-3">
          {day && <>
          <div className="flex items-baseline justify-between gap-2">
            <h2 className="text-lg font-medium">当天时间线</h2>
            <span className="text-xs text-ink-soft">{day.courses.length} 节课{day.archived ? "" : " · " + free.length + " 段空档"}</span>
          </div>
          {(date <= today || done > 0) && day.items.length > 0 && <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-ink-soft">
            <span>已完成 {done} · 未完成 {unfinished} · 未记录 {day.items.length - done - unfinished}</span>
            {done > 0 && <button type="button" className={quietButton} aria-pressed={hideDone}
              onClick={() => setHideDone(!hideDone)}>{hideDone ? "显示已完成" : "收起已完成"}</button>}
          </div>}
          {day.courses.filter((course) => course.allDay).map((course) =>
            <div key={course.key} className="rounded-xl border border-line bg-card p-3 text-sm">
              <span className="mr-3 text-accent-deep">全天</span>{course.title}
            </div>)}
          <ol className="space-y-2">
            {groups.map((entry) => {
              if ((entry.kind === "gap" && day.archived) || (entry.kind === "item" && hideDone && entry.item.status === "done")) return null;
              const time = formatMinute(entry.start) + "–" + formatMinute(entry.end);
              if (entry.kind === "gap") return <li key={"gap-" + entry.start}>
                <button className="flex w-full items-center justify-between gap-3 rounded-xl border border-dashed border-line px-4 py-2 text-left text-sm text-ink-soft hover:border-accent disabled:opacity-60"
                  disabled={!canEdit || itemControlsDisabled} onClick={() => openDraft({ date, startTime: formatMinute(entry.start), endTime: formatMinute(Math.min(entry.end, entry.start + 60)) })}>
                  <span className="tnum">{time} 空档</span><span className="text-accent-deep">＋ 安排</span>
                </button>
              </li>;
              const course = entry.kind === "course" ? entry.course : null;
              return <li key={course?.key ?? (entry.kind === "item" ? entry.item.id : "")}
                className="flex min-w-0 items-start gap-3 rounded-xl border border-line bg-card px-4 py-3 shadow-card">
                <span aria-hidden className="mt-0.5 text-accent">
                  {course ? <IconCalendar className="size-4" /> : <IconClock className="size-4" />}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="tnum text-xs text-ink-soft">{time} · {course ? "课程" : "安排"}</p>
                  <p className="break-words text-sm font-medium">{entry.kind === "course" ? entry.course.title : entry.item.title}</p>
                  {entry.kind === "item" && itemResult(entry.item)}
                  {course?.location && <p className="break-words text-xs text-ink-soft">{course.location}</p>}
                  {entry.kind === "item" && entry.overlap && <p className="mt-1 text-xs font-medium text-warn">与课程重叠</p>}
                </div>
                {entry.kind === "item" && itemActions(entry.item)}
              </li>;
            })}
          </ol>
          {day.archived && <p className="text-sm text-ink-soft">已归档，可补记已有安排。</p>}
          </>}
        </section>
        <aside className="min-w-0 space-y-3" aria-label="规划工具">
          {draft && <PlannerEditor draft={draft} saved={saved} minDate={earliest} today={today} tasks={tasks}
            issuedAt={issuedAt}
            onSaved={finished} onClose={closeDraft} />}
          <section className="rounded-2xl border border-line bg-card p-4 shadow-card">
            <div className="flex items-center justify-between gap-2">
              <h2 className="font-medium">待安排</h2>
              {canEdit && <button className={quietButton} disabled={itemControlsDisabled} onClick={() => openDraft({ date })}>添加</button>}
            </div>
            {unscheduled.length ? <ul className="mt-2 divide-y divide-line">{unscheduled.map((item) =>
              <li className="flex items-center justify-between gap-2 py-2 text-sm" key={item.id}>
                <div className="min-w-0 break-words">{item.title}{itemResult(item)}</div>
                {itemActions(item)}
              </li>)}</ul> : <p className="mt-2 text-sm text-ink-soft">未指定时间的安排会显示在这里。</p>}
          </section>
          {!day?.archived && <PlannerImport onImported={(status) => { setMessage(status); void readDay(date); }} />}
          {!day?.archived && <PlannerReminderSettings />}
        </aside>
      </div>}
    </div>
  );
}
