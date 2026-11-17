import { NextResponse } from "next/server";
import { classifyTasks } from "@/lib/quadrant-ai";

export const dynamic = "force-dynamic";

/** 批量给未完成任务打四象限标签；?force=1 重新分类全部 */
export async function POST(req: Request) {
  const force = new URL(req.url).searchParams.get("force") === "1";
  try {
    const result = await classifyTasks(force);
    return NextResponse.json(result);
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "分类失败" },
      { status: 500 }
    );
  }
}
