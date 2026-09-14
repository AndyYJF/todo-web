import { NextRequest, NextResponse } from "next/server";
import { AUTH_COOKIE, AUTH_MAX_AGE, checkPassword, makeToken } from "@/lib/auth";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  const password = typeof body?.password === "string" ? body.password : "";

  if (!checkPassword(password)) {
    // 恒定延迟，防时序探测
    await new Promise((r) => setTimeout(r, 400));
    return NextResponse.json({ error: "密码错误" }, { status: 401 });
  }

  const res = NextResponse.json({ ok: true });
  res.cookies.set(AUTH_COOKIE, await makeToken(), {
    httpOnly: true,
    sameSite: "lax",
    secure: true,
    maxAge: AUTH_MAX_AGE,
    path: "/",
  });
  return res;
}
