import { getDb } from "./db";
import { listTasks } from "./tasks";
import type { Task } from "./types";

export interface ClassifyResult {
  classified: number;
  failed: number;
  aiUsed: boolean;
  error?: string;
}

/** 规则兜底：按截止时间和关键词给出象限 */
function ruleBased(t: Task): { urgent: boolean; important: boolean } {
  const text = `${t.title} ${t.note}`.toLowerCase();
  const important =
    t.priority === "high" ||
    /考试|测验|报名|提交|截止|申请|入党|答辩|缴费|签到|打卡|注册|确认|审核/.test(text);
  let urgent = false;
  if (t.dueAt) {
    const hours = (new Date(t.dueAt.replace(" ", "T")).getTime() - Date.now()) / 3600000;
    urgent = hours <= 48; // 含已超期（负数）
  }
  return { urgent, important };
}

interface AiVerdict {
  id: number;
  urgent: boolean;
  important: boolean;
}

async function classifyWithAi(batch: Task[]): Promise<AiVerdict[]> {
  const endpoint = process.env.MODEL_ENDPOINT;
  const key = process.env.MODEL_API_KEY;
  if (!endpoint || !key) throw new Error("未配置模型");

  const items = batch.map((t) => ({
    id: t.id,
    title: t.title,
    note: t.note.slice(0, 300),
    due: t.dueAt,
    project: t.project,
  }));
  const body = JSON.stringify({
    model: process.env.MODEL_NAME ?? "gemini-3.8-flash-high",
    messages: [
      {
        role: "system",
        content:
          "你是艾森豪威尔矩阵分类器。紧急性=是否需要尽快处理（临近截止/超期/时效性强）；重要性=对学业/发展/义务的影响大小（考试、报名、提交、党组织事务通常重要；日常闲聊、可忽略通知不重要）。只输出 JSON 数组，每项 {\"id\":数字,\"urgent\":布尔,\"important\":布尔}，不要多余文字。",
      },
      {
        role: "user",
        content: `当前时间 ${new Date().toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" })}（UTC+8）。分类这些任务：\n${JSON.stringify(items)}`,
      },
    ],
    temperature: 0,
  });

  const { httpRequest } = await import("./httpget");
  const res = await httpRequest(`${endpoint.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    body,
    timeoutMs: 60000,
    headers: { authorization: `Bearer ${key}` },
  });
  if (res.status !== 200) throw new Error(`模型接口 ${res.status}`);
  const data = JSON.parse(res.body.toString("utf8"));
  const content: string = data.choices?.[0]?.message?.content ?? "";
  const match = content.match(/\[[\s\S]*\]/);
  if (!match) throw new Error("模型未返回 JSON 数组");
  const parsed = JSON.parse(match[0]) as AiVerdict[];
  return parsed.filter(
    (v) => typeof v.id === "number" && typeof v.urgent === "boolean" && typeof v.important === "boolean"
  );
}

/** 给未分类的未完成任务打象限标签；AI 优先，失败回退规则 */
export async function classifyTasks(force = false): Promise<ClassifyResult> {
  const pending = listTasks({ view: "all" }).filter((t) => !t.done);
  const targets = force
    ? pending
    : pending.filter((t) => t.urgent === null || t.important === null);
  if (!targets.length) return { classified: 0, failed: 0, aiUsed: false };

  const verdicts = new Map<number, AiVerdict>();
  let aiUsed = false;
  let lastError: string | undefined;

  // 每批 20 条，控制 token
  for (let i = 0; i < targets.length; i += 20) {
    const batch = targets.slice(i, i + 20);
    try {
      const vs = await classifyWithAi(batch);
      aiUsed = true;
      for (const v of vs) verdicts.set(v.id, v);
    } catch (e) {
      lastError = e instanceof Error ? e.message : String(e);
      break; // AI 不可用则整体走规则
    }
  }

  const db = getDb();
  const stmt = db.prepare(
    "UPDATE tasks SET urgent = ?, important = ?, updated_at = updated_at WHERE id = ?"
  );
  let classified = 0;
  let failed = 0;
  for (const t of targets) {
    const v = verdicts.get(t.id);
    const { urgent, important } = v ?? ruleBased(t);
    if (!v) failed++;
    stmt.run(urgent ? 1 : 0, important ? 1 : 0, t.id);
    classified++;
  }
  return { classified, failed, aiUsed, error: aiUsed ? undefined : lastError };
}
