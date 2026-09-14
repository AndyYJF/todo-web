// 会话令牌：HMAC-SHA256 签名的过期时间戳。
// 只用 Web Crypto（crypto.subtle），Edge middleware 和 Node 路由通用。

const COOKIE_NAME = "todo_session";
const MAX_AGE_SEC = 30 * 86400; // 30 天

function secret(): string {
  return process.env.TODO_PASSWORD || "todo-dev-default";
}

async function hmacHex(data: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function makeToken(): Promise<string> {
  const exp = Date.now() + MAX_AGE_SEC * 1000;
  return `${exp}.${await hmacHex(String(exp))}`;
}

export async function verifyToken(token: string | undefined): Promise<boolean> {
  if (!token) return false;
  const i = token.indexOf(".");
  if (i <= 0) return false;
  const exp = Number(token.slice(0, i));
  if (!Number.isFinite(exp) || exp < Date.now()) return false;
  const expected = await hmacHex(String(exp));
  return safeEqual(token.slice(i + 1), expected);
}

/** 校验登录密码（常数时间比较） */
export function checkPassword(input: string): boolean {
  return safeEqual(input, secret());
}

export const AUTH_COOKIE = COOKIE_NAME;
export const AUTH_MAX_AGE = MAX_AGE_SEC;
