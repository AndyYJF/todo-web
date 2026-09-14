"use client";

import type { Task, TaskInput, TaskPatch } from "./types";
import type { TaskView } from "./tasks";

async function req<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    headers: { "content-type": "application/json" },
    ...init,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `请求失败 ${res.status}`);
  }
  return res.json();
}

export async function fetchTasks(
  view: TaskView,
  project?: string
): Promise<Task[]> {
  const sp = new URLSearchParams({ view });
  if (project) sp.set("project", project);
  const data = await req<{ tasks: Task[] }>(`/api/tasks?${sp}`);
  return data.tasks;
}

export async function fetchProjects(): Promise<string[]> {
  const data = await req<{ projects: string[] }>("/api/tasks?meta=projects");
  return data.projects;
}

export async function createTask(input: TaskInput): Promise<Task> {
  const data = await req<{ task: Task }>("/api/tasks", {
    method: "POST",
    body: JSON.stringify(input),
  });
  return data.task;
}

export async function patchTask(id: number, patch: TaskPatch): Promise<Task> {
  const data = await req<{ task: Task }>(`/api/tasks/${id}`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
  return data.task;
}

export async function removeTask(id: number): Promise<void> {
  await req(`/api/tasks/${id}`, { method: "DELETE" });
}
