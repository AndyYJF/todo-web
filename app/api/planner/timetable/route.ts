import { MAX_ICS_BYTES, parseCourseCalendar } from "@/lib/planner/ics";
import { invalid, PlannerError, record, requireDate, requireId, requireVersion } from "@/lib/planner/domain";
import { handlePlanner, plannerJson } from "@/lib/planner/http";
import { getPlanner } from "@/lib/planner/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function POST(request: Request) {
  return handlePlanner(async () => {
    const body = record(await plannerJson(request, MAX_ICS_BYTES * 6 + 4096));
    if (typeof body.ics !== "string" || (body.action !== "preview" && body.action !== "commit")) {
      invalid("请提供 iCalendar 文本和预览或确认操作");
    }
    const { courses, checksum, eventCount } = await parseCourseCalendar(body.ics);
    if (body.action === "preview") return { ...getPlanner().previewImport(courses, checksum), eventCount };
    if (body.checksum !== checksum) throw new PlannerError(409, "import_changed", "文件已变化，请重新预览");
    return getPlanner().commitImport(courses, checksum, requireDate(body.effectiveFrom),
      requireVersion(body.baseVersion, 0), requireId(body.operationId), requireVersion(body.issuedAt));
  });
}
