import { businessDate } from "@/lib/planner/dates";
import { invalid, requireDate } from "@/lib/planner/domain";
import { handlePlanner, plannerJson } from "@/lib/planner/http";
import { getPlanner } from "@/lib/planner/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(request: Request) {
  return handlePlanner(() => {
    const query = new URL(request.url).searchParams;
    if (query.get("view") === "history") {
      const before = query.get("before");
      const limit = Number(query.get("limit") ?? 20);
      if (!Number.isInteger(limit) || limit < 1 || limit > 50) invalid("每页最多 50 天");
      return getPlanner().history(before === null ? null : requireDate(before), limit);
    }
    return getPlanner().day(requireDate(query.get("date") ?? businessDate()));
  });
}

export function POST(request: Request) {
  return handlePlanner(async () => getPlanner().mutate(await plannerJson(request, 48 * 1024)));
}
