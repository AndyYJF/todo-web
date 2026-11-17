import { NextRequest, NextResponse } from "next/server";
import { httpRequest } from "@/lib/httpget";

/** 允许代理的图片源（防开放代理滥用）：校园事务服务器新旧 IP */
const ALLOWED = [/^https:\/\/campus\.andy-y\.cn\//, /^http:\/\/84\.54\.2\.93:8620\//, /^http:\/\/139\.224\.71\.200:8620\//];

export async function GET(req: NextRequest) {
  const u = req.nextUrl.searchParams.get("u") ?? "";
  if (!ALLOWED.some((re) => re.test(u))) {
    return NextResponse.json({ error: "不允许的来源" }, { status: 403 });
  }
  // 上游网络不稳定：重试 2 次（用 node:http 直连，绕开 Next 包装 fetch 的问题）
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await httpRequest(u, { timeoutMs: 20000 });
      if (r.status < 200 || r.status >= 300) continue;
      return new Response(new Uint8Array(r.body), {
        headers: {
          "Content-Type": (r.headers["content-type"] as string) ?? "image/jpeg",
          "Cache-Control": "private, max-age=86400",
        },
      });
    } catch {
      // 重试
    }
  }
  return NextResponse.json({ error: "图片拉取失败" }, { status: 502 });
}
