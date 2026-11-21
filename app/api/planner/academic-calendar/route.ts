import { getDb } from "@/lib/db";
import { academicCalendar } from "@/lib/planner/academic-calendar";
import { businessDate } from "@/lib/planner/dates";
import { requireDate } from "@/lib/planner/domain";
import { handlePlanner } from "@/lib/planner/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(request: Request) {
  return handlePlanner(() => academicCalendar(getDb(),
    requireDate(new URL(request.url).searchParams.get("date") ?? businessDate())));
}
