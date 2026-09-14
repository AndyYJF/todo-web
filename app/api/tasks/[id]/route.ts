import { NextRequest, NextResponse } from "next/server";
import { deleteTask, getTask, updateTask } from "@/lib/tasks";
import { writebackStatus } from "@/lib/campus-sync";

export const dynamic = "force-dynamic";

type Ctx = { params: Promise<{ id: string }> };

async function parseId(ctx: Ctx): Promise<number | null> {
  const { id } = await ctx.params;
  const n = Number(id);
  return Number.isInteger(n) && n > 0 ? n : null;
}

export async function GET(_req: NextRequest, ctx: Ctx) {
  const id = await parseId(ctx);
  if (!id) return NextResponse.json({ error: "id 无效" }, { status: 400 });
  const task = getTask(id);
  if (!task) return NextResponse.json({ error: "不存在" }, { status: 404 });
  return NextResponse.json({ task });
}

export async function PATCH(req: NextRequest, ctx: Ctx) {
  const id = await parseId(ctx);
  if (!id) return NextResponse.json({ error: "id 无效" }, { status: 400 });
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return NextResponse.json({ error: "请求体无效" }, { status: 400 });
  }
  const task = updateTask(id, body);
  if (!task) return NextResponse.json({ error: "不存在" }, { status: 404 });
  // 校园事务任务：勾选状态回写上游（不阻塞响应，失败靠下次全量同步校准）
  if (task.externalId && typeof body.done === "boolean") {
    writebackStatus(task.externalId, task.externalRev, body.done).catch(
      () => {}
    );
  }
  return NextResponse.json({ task });
}

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  const id = await parseId(ctx);
  if (!id) return NextResponse.json({ error: "id 无效" }, { status: 400 });
  if (!deleteTask(id))
    return NextResponse.json({ error: "不存在" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
