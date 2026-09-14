import { NextResponse } from "next/server";
import { lastSyncResult, syncCampusTasks } from "@/lib/campus-sync";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({ last: lastSyncResult() });
}

export async function POST() {
  const result = await syncCampusTasks();
  return NextResponse.json(result, { status: result.error ? 502 : 200 });
}
