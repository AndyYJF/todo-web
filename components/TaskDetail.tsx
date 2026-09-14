"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task, TaskInput, TaskPatch, Priority } from "@/lib/types";
import {
  durationHours,
  fmtShort,
  isOverdue,
} from "@/lib/datetime";
import DateTimePicker from "./DateTimePicker";
import NoteContent from "./NoteContent";

export default function TaskDetail({
  task,
  creating,
  startEdit,
  projects,
  onClose,
  onSave,
  onDelete,
  onToggleDone,
  onTogglePin,
}: {
  task: Task | null;
  creating: boolean;
  startEdit: boolean;
  projects: string[];
  onClose: () => void;
  onSave: (input: TaskInput, id?: number) => Promise<void>;
  onDelete: (id: number) => Promise<void>;
  onToggleDone: (t: Task) => Promise<void>;
  onTogglePin: (t: Task) => Promise<void>;
}) {
  const [editing, setEditing] = useState(creating || startEdit);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [startAt, setStartAt] = useState<string | null>(null);
  const [dueAt, setDueAt] = useState<string | null>(null);
  const [priority, setPriority] = useState<Priority>("normal");
  const [project, setProject] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setEditing(creating || startEdit);
    setTitle(task?.title ?? "");
    setNote(task?.note ?? "");
    setStartAt(task?.startAt ?? null);
    setDueAt(task?.dueAt ?? null);
    setPriority(task?.priority ?? "normal");
    setProject(task?.project ?? "");
  }, [task, creating, startEdit]);

  // Esc 关闭
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  async function save() {
    if (!title.trim()) return;
    setSaving(true);
    try {
      const input: TaskInput & TaskPatch = {
        title: title.trim(),
        note,
        startAt,
        dueAt,
        priority,
        project: project.trim(),
      };
      await onSave(input, task?.id);
    } finally {
      setSaving(false);
    }
  }

  const overdue = task ? isOverdue(task) : false;
  const dur = task ? durationHours(task.startAt, task.dueAt) : null;

  const inputCls =
    "w-full bg-paper border border-line rounded-xl px-3.5 py-2.5 text-sm outline-none focus:border-ink/40 transition-colors";
  const labelCls =
    "block text-[10px] uppercase tracking-[0.18em] text-ink-soft mb-1.5";

  return (
    <div className="fixed inset-0 z-50 md:sticky md:top-0 md:inset-auto md:w-[420px] md:shrink-0 h-screen p-0 md:p-5 flex items-stretch md:items-center">
      <motion.div
        initial={{ opacity: 0, y: 24, scale: 0.97 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 24, scale: 0.97 }}
        transition={{ type: "spring", stiffness: 400, damping: 34 }}
        className="w-full md:max-h-full bg-card md:border md:border-line md:rounded-3xl shadow-lift flex flex-col overflow-hidden"
      >
        {/* 头部 */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4">
          <div className="text-[10px] uppercase tracking-[0.22em] text-ink-soft">
            {creating ? "New Task" : editing ? "Edit" : "Detail"}
          </div>
          <button
            onClick={onClose}
            aria-label="关闭"
            className="w-8 h-8 rounded-full text-ink-soft hover:bg-paper hover:text-ink grid place-items-center text-lg leading-none transition-colors"
          >
            ×
          </button>
        </div>

        {/* 内容 */}
        <div className="overflow-y-auto px-6 pb-4">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={creating ? "new" : (task?.id ?? "none")}
              initial={{ opacity: 0, x: 14 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -14 }}
              transition={{ duration: 0.14, ease: "easeOut" }}
            >
          {editing ? (
            <div className="space-y-5">
              <div>
                <label className={labelCls}>标题</label>
                <input
                  autoFocus
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="要做什么？"
                  className={inputCls}
                  onKeyDown={(e) => e.key === "Enter" && save()}
                />
              </div>
              <div>
                <label className={labelCls}>备注</label>
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  rows={3}
                  className={`${inputCls} resize-none`}
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={labelCls}>开始</label>
                  <DateTimePicker
                    value={startAt}
                    onChange={setStartAt}
                    placeholder="未设置"
                  />
                </div>
                <div>
                  <label className={labelCls}>截止</label>
                  <DateTimePicker
                    value={dueAt}
                    onChange={setDueAt}
                    placeholder="未设置"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={labelCls}>优先级</label>
                  <div className="flex bg-paper border border-line rounded-xl p-1">
                    {(
                      [
                        ["low", "低"],
                        ["normal", "一般"],
                        ["high", "高"],
                      ] as [Priority, string][]
                    ).map(([val, label]) => (
                      <button
                        key={val}
                        type="button"
                        onClick={() => setPriority(val)}
                        className={`relative flex-1 py-1.5 rounded-lg text-xs transition-colors ${
                          priority === val
                            ? "text-paper"
                            : "text-ink-soft hover:text-ink"
                        }`}
                      >
                        {priority === val && (
                          <motion.span
                            layoutId="pri-pill"
                            transition={{
                              type: "spring",
                              stiffness: 500,
                              damping: 40,
                            }}
                            className="absolute inset-0 bg-ink rounded-lg"
                          />
                        )}
                        <span className="relative z-10">{label}</span>
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <label className={labelCls}>项目</label>
                  <input
                    value={project}
                    onChange={(e) => setProject(e.target.value)}
                    list="project-list"
                    placeholder="可留空"
                    className={inputCls}
                  />
                  <datalist id="project-list">
                    {projects.map((p) => (
                      <option key={p} value={p} />
                    ))}
                  </datalist>
                </div>
              </div>
            </div>
          ) : task ? (
            <div>
              <h2
                className={`font-display text-[32px] leading-[1.15] tracking-tight ${
                  task.done ? "line-through text-ink-soft" : ""
                }`}
              >
                {task.title}
              </h2>

              {(overdue || task.quick === 1 || task.priority === "high" || task.project) && (
                <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                  {overdue && (
                    <span className="px-2 py-0.5 rounded-md bg-danger-soft text-danger font-medium">
                      已超期
                    </span>
                  )}
                  {task.priority === "high" && (
                    <span className="px-2 py-0.5 rounded-md bg-warn-soft text-warn font-medium">
                      高优先
                    </span>
                  )}
                  {task.quick === 1 && (
                    <span className="px-2 py-0.5 rounded-md bg-accent-soft text-accent-deep">
                      快速任务
                    </span>
                  )}
                  {task.project && (
                    <span className="px-2 py-0.5 rounded-md border border-line text-ink-soft">
                      {task.project}
                    </span>
                  )}
                </div>
              )}

              <dl className="mt-6 text-sm divide-y divide-line/70">
                {[
                  ["开始", fmtShort(task.startAt) || "—"],
                  ["截止", fmtShort(task.dueAt) || "—"],
                  ["时长", dur !== null ? `${dur} 小时` : "—"],
                  ["创建", task.createdAt],
                ].map(([k, v]) => (
                  <div key={k} className="flex items-center py-3">
                    <dt className="w-14 text-[11px] uppercase tracking-[0.15em] text-ink-soft shrink-0">
                      {k}
                    </dt>
                    <dd className="tnum">{v}</dd>
                  </div>
                ))}
                {task.note && (
                  <div className="py-3">
                    <dt className="text-[11px] uppercase tracking-[0.15em] text-ink-soft mb-1.5">
                      备注
                    </dt>
                    <dd>
                      <NoteContent text={task.note} />
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          ) : null}
            </motion.div>
          </AnimatePresence>
        </div>

        {/* 底部操作 */}
        <div className="px-6 py-5 border-t border-line flex items-center gap-2.5">
          {editing ? (
            <>
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={save}
                disabled={saving || !title.trim()}
                className="flex-1 bg-ink text-paper rounded-xl py-3 text-sm font-medium hover:bg-black disabled:opacity-40 transition-colors"
              >
                {saving ? "保存中…" : creating ? "创建任务" : "保存修改"}
              </motion.button>
              {!creating && (
                <button
                  onClick={() => setEditing(false)}
                  className="px-5 py-3 rounded-xl text-sm text-ink-soft hover:text-ink hover:bg-paper transition-colors"
                >
                  取消
                </button>
              )}
            </>
          ) : task ? (
            <>
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={() => onToggleDone(task)}
                className={`flex-1 rounded-xl py-3 text-sm font-medium transition-colors ${
                  task.done
                    ? "border border-line hover:bg-paper"
                    : "bg-ink text-paper hover:bg-black"
                }`}
              >
                {task.done ? "取消完成" : "标记完成"}
              </motion.button>
              <button
                onClick={() => onTogglePin(task)}
                className={`px-4 py-3 rounded-xl text-sm transition-colors ${
                  task.pinned
                    ? "text-accent bg-accent-soft"
                    : "text-ink-soft hover:text-accent hover:bg-accent-soft"
                }`}
              >
                {task.pinned ? "取消置顶" : "置顶"}
              </button>
              <button
                onClick={() => setEditing(true)}
                className="px-5 py-3 rounded-xl text-sm text-ink-soft hover:text-ink hover:bg-paper transition-colors"
              >
                编辑
              </button>
              <button
                onClick={() => {
                  if (window.confirm(`删除「${task.title}」？不可恢复。`))
                    onDelete(task.id);
                }}
                className="px-4 py-3 rounded-xl text-sm text-danger/80 hover:text-danger hover:bg-danger-soft transition-colors"
              >
                删除
              </button>
            </>
          ) : null}
        </div>
      </motion.div>
    </div>
  );
}
