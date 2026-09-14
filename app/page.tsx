"use client";

import { useCallback, useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Task, TaskInput, TaskPatch } from "@/lib/types";
import {
  createTask,
  fetchProjects,
  fetchTasks,
  patchTask,
  removeTask,
} from "@/lib/api";
import Sidebar, { type ViewKey } from "@/components/Sidebar";
import TodayView from "@/components/TodayView";
import AllTasksView from "@/components/AllTasksView";
import CalendarView from "@/components/CalendarView";
import GanttView from "@/components/GanttView";
import ProjectsView from "@/components/ProjectsView";
import PinsView from "@/components/PinsView";
import SettingsView from "@/components/SettingsView";
import TaskDetail from "@/components/TaskDetail";

export default function Home() {
  const [view, setView] = useState<ViewKey>("today");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [todayCount, setTodayCount] = useState(0);
  const [projects, setProjects] = useState<string[]>([]);
  const [selected, setSelected] = useState<Task | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [startEdit, setStartEdit] = useState(false);
  const [error, setError] = useState("");
  const [lastSync, setLastSync] = useState<Date | null>(null);
  const [loading, setLoading] = useState(true);
  const [mobileNav, setMobileNav] = useState(false);

  const reload = useCallback(async (background = false) => {
    if (!background) setLoading(true);
    try {
      const list =
        view === "today"
          ? await fetchTasks("today")
          : view === "pinned"
            ? await fetchTasks("pinned")
            : await fetchTasks("all");
      const [todayList, projs] = await Promise.all([
        view === "today" ? Promise.resolve(list) : fetchTasks("today"),
        fetchProjects(),
      ]);
      setTasks(list);
      setTodayCount(todayList.filter((t) => !t.done).length);
      setProjects(projs);
      setError("");
      setLastSync(new Date());
      // 详情面板打开时同步最新数据
      setSelected((cur) =>
        cur ? (list.find((t) => t.id === cur.id) ?? cur) : cur
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "加载失败");
    } finally {
      setLoading(false);
    }
  }, [view]);

  useEffect(() => {
    reload();
  }, [reload]);

  async function toggleDone(t: Task) {
    await patchTask(t.id, { done: !t.done });
    // 任务离开当前视图（如今日里勾完成）→ 关掉详情面板
    if (view === "today" && !t.done && selected?.id === t.id) closeDrawer();
    await reload(true);
  }

  async function togglePin(t: Task) {
    await patchTask(t.id, { pinned: !t.pinned });
    // 磁贴页取消置顶 → 任务离开当前视图，关掉详情面板
    if (view === "pinned" && t.pinned === 1 && selected?.id === t.id)
      closeDrawer();
    await reload(true);
  }

  async function save(input: TaskInput & TaskPatch, id?: number) {
    if (id) await patchTask(id, input);
    else await createTask(input);
    setDrawerOpen(false);
    setSelected(null);
    setCreating(false);
    await reload(true);
  }

  async function remove(id: number) {
    await removeTask(id);
    setDrawerOpen(false);
    setSelected(null);
    await reload(true);
  }

  function openTask(t: Task, edit = false) {
    setSelected(t);
    setCreating(false);
    setStartEdit(edit);
    setDrawerOpen(true);
  }

  function openCreate() {
    setSelected(null);
    setCreating(true);
    setStartEdit(true);
    setDrawerOpen(true);
  }

  function closeDrawer() {
    setDrawerOpen(false);
    setSelected(null);
    setCreating(false);
    setStartEdit(false);
  }

  async function quickCreate(title: string, dueAt: string | null) {
    await createTask({ title, quick: true, dueAt });
    await reload(true);
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar
        view={view}
        todayCount={todayCount}
        projectsCount={projects.length}
        lastSync={lastSync}
        open={mobileNav}
        onNavigate={(v) => {
          setView(v);
          setMobileNav(false);
        }}
      />

      {/* 移动端遮罩 */}
      {mobileNav && (
        <div
          className="fixed inset-0 z-40 bg-ink/25 md:hidden"
          onClick={() => setMobileNav(false)}
        />
      )}

      <div className="flex-1 min-w-0 flex flex-col">
        {/* 移动端顶栏 */}
        <div className="md:hidden sticky top-0 z-30 flex items-center gap-3 px-4 py-3 bg-card border-b border-line">
          <button
            onClick={() => setMobileNav(true)}
            aria-label="打开菜单"
            className="w-9 h-9 grid place-items-center rounded-lg hover:bg-paper text-xl leading-none"
          >
            ☰
          </button>
          <div className="font-display text-xl tracking-tight">
            Todo<span className="text-accent">.</span>
          </div>
        </div>

      <main className="flex-1 min-w-0 px-4 md:px-10 py-6 md:py-10">
        {error && (
          <div className="mb-4 bg-danger-soft text-danger text-sm rounded-xl px-4 py-2.5">
            加载失败：{error}
            <button onClick={() => reload()} className="underline ml-2">
              重试
            </button>
          </div>
        )}
        <AnimatePresence mode="wait">
          <motion.div
            key={view}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18, ease: "easeOut" }}
          >
            {loading ? (
              <div className="max-w-2xl space-y-3 pt-2" aria-label="加载中">
                <div className="h-10 w-48 rounded-xl bg-line/60 animate-pulse" />
                {[0, 1, 2].map((i) => (
                  <div
                    key={i}
                    className="h-[68px] rounded-2xl bg-line/50 animate-pulse"
                    style={{ animationDelay: `${i * 120}ms` }}
                  />
                ))}
              </div>
            ) : (
              <>
            {view === "today" && (
              <TodayView
                tasks={tasks}
                onQuickCreate={quickCreate}
                onNewDetail={openCreate}
                onOpen={(t) => openTask(t)}
                onToggle={toggleDone}
                onEdit={(t) => openTask(t, true)}
              />
            )}
            {view === "all" && (
              <AllTasksView
                tasks={tasks}
                projects={projects}
                onOpen={(t) => openTask(t)}
                onToggle={toggleDone}
              />
            )}
            {view === "calendar" && (
              <CalendarView
                tasks={tasks}
                onOpen={(t) => openTask(t)}
                onToggle={toggleDone}
              />
            )}
            {view === "gantt" && (
              <GanttView tasks={tasks} onOpen={(t) => openTask(t)} />
            )}
            {view === "projects" && (
              <ProjectsView
                tasks={tasks}
                onOpen={(t) => openTask(t)}
                onToggle={toggleDone}
              />
            )}
            {view === "pinned" && (
              <PinsView
                tasks={tasks}
                onOpen={(t) => openTask(t)}
                onToggle={toggleDone}
              />
            )}
            {view === "settings" && <SettingsView tasks={tasks} />}
              </>
            )}
          </motion.div>
        </AnimatePresence>
      </main>
      </div>

      <AnimatePresence>
        {drawerOpen && (
          <TaskDetail
            task={selected}
            creating={creating}
            startEdit={startEdit}
            projects={projects}
            onClose={closeDrawer}
            onSave={save}
            onDelete={remove}
            onToggleDone={toggleDone}
            onTogglePin={togglePin}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
