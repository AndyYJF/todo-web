import { NextRequest, NextResponse } from "next/server";
import { httpRequest } from "@/lib/httpget";

import { campusImageUrl } from "@/lib/campus-image";

export async function GET(req: NextRequest) {
  const u = campusImageUrl(req.nextUrl.searchParams.get("u") ?? "");
  if (!u) {
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
