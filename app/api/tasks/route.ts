import { NextRequest, NextResponse } from "next/server";
import { createTask, listProjects, listTasks, type TaskView } from "@/lib/tasks";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  if (sp.get("meta") === "projects") {
    return NextResponse.json({ projects: listProjects() });
  }
  const view = (sp.get("view") ?? "today") as TaskView;
  const project = sp.get("project") ?? undefined;
  return NextResponse.json({ tasks: listTasks({ view, project }) });
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body?.title || typeof body.title !== "string") {
    return NextResponse.json({ error: "title 必填" }, { status: 400 });
  }
  const task = createTask({
    title: body.title,
    note: body.note,
    startAt: body.startAt ?? null,
    dueAt: body.dueAt ?? null,
    priority: body.priority,
    project: body.project,
    quick: body.quick === true,
    pinned: body.pinned === true,
  });
  return NextResponse.json({ task }, { status: 201 });
}
