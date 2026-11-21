import { handlePlanner, plannerJson } from "@/lib/planner/http";
import { getPlanner } from "@/lib/planner/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET() {
  return handlePlanner(() => getPlanner().settings());
}

export function PUT(request: Request) {
  return handlePlanner(async () => getPlanner().saveSettings(await plannerJson(request, 4096)));
}
