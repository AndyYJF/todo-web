import { PlannerError } from "./domain";

export async function boundedText(message: Request | Response, limit: number): Promise<string> {
  if (Number(message.headers.get("content-length")) > limit) {
    if (message.body) await message.body.cancel();
    throw new PlannerError(413, "body_too_large", "正文超过大小限制");
  }
  if (!message.body) return "";
  const reader = message.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let bytes = 0, output = "";
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return output + decoder.decode();
      bytes += value.byteLength;
      if (bytes > limit) throw new PlannerError(413, "body_too_large", "正文超过大小限制");
      output += decoder.decode(value, { stream: true });
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
}

export async function plannerJson(request: Request, limit: number): Promise<unknown> {
  if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
    throw new PlannerError(415, "invalid_content_type", "请使用 application/json");
  }
  try {
    return JSON.parse(await boundedText(request, limit));
  } catch (error) {
    if (error instanceof PlannerError) throw error;
    throw new PlannerError(400, "invalid_json", "需要有效的 UTF-8 JSON 正文");
  }
}

export function plannerResponse(data: unknown, status = 200): Response {
  return Response.json(data, { status, headers: { "Cache-Control": "private, no-store" } });
}

export async function handlePlanner(work: () => unknown | Promise<unknown>): Promise<Response> {
  try {
    return plannerResponse(await work());
  } catch (error) {
    if (error instanceof PlannerError) {
      return plannerResponse({ error: error.message, code: error.code, current: error.current }, error.status);
    }
    if (error && typeof error === "object" && "errcode" in error && error.errcode === 5) {
      return plannerResponse({ error: "规划数据正在保存，请重试", code: "database_busy" }, 503);
    }
    throw error;
  }
}
