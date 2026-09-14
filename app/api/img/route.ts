import { NextRequest, NextResponse } from "next/server";

/** 允许代理的图片源（防开放代理滥用） */
const ALLOWED = [/^http:\/\/139\.224\.71\.200:8620\//];

export async function GET(req: NextRequest) {
  const u = req.nextUrl.searchParams.get("u") ?? "";
  if (!ALLOWED.some((re) => re.test(u))) {
    return NextResponse.json({ error: "不允许的来源" }, { status: 403 });
  }
  // 上游网络不稳定：重试 2 次
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetch(u, { signal: AbortSignal.timeout(20000) });
      if (!r.ok || !r.body) continue;
      return new Response(r.body, {
        headers: {
          "Content-Type": r.headers.get("Content-Type") ?? "image/jpeg",
          "Cache-Control": "private, max-age=86400",
        },
      });
    } catch {
      // 重试
    }
  }
  return NextResponse.json({ error: "图片拉取失败" }, { status: 502 });
}
