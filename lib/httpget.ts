import http from "node:http";
import https from "node:https";

/** 绕过 Next 对全局 fetch 的包装（请求上下文里会出现莫名 "fetch failed"），直接用 node:http/https */
export function httpRequest(
  url: string,
  opts: { method?: string; body?: string; timeoutMs?: number; redirects?: number; headers?: Record<string, string> } = {}
): Promise<{ status: number; headers: http.IncomingHttpHeaders; body: Buffer }> {
  const { method = "GET", body, timeoutMs = 20000, redirects = 3 } = opts;
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const mod = u.protocol === "https:" ? https : http;
    const req = mod.request(
      {
        hostname: u.hostname,
        port: u.port || (u.protocol === "https:" ? 443 : 80),
        path: u.pathname + u.search,
        method,
        headers: body
          ? {
              "content-type": "application/json",
              "content-length": Buffer.byteLength(body),
              ...(opts.headers ?? {}),
            }
          : { ...(opts.headers ?? {}) },
        timeout: timeoutMs,
      },
      (res) => {
        const status = res.statusCode ?? 0;
        // 跟随重定向（301/302/303/307/308）
        if (redirects > 0 && status >= 300 && status < 400 && res.headers.location) {
          res.resume();
          const next = new URL(res.headers.location, url).toString();
          resolve(httpRequest(next, { ...opts, redirects: redirects - 1 }));
          return;
        }
        const chunks: Buffer[] = [];
        res.on("data", (d) => chunks.push(d));
        res.on("end", () =>
          resolve({ status, headers: res.headers, body: Buffer.concat(chunks) })
        );
        res.on("error", reject);
      }
    );
    req.on("timeout", () => req.destroy(new Error(`请求超时(${timeoutMs}ms)`)));
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
  });
}

export async function httpGetJson<T>(url: string, timeoutMs?: number): Promise<T> {
  const r = await httpRequest(url, { timeoutMs });
  if (r.status < 200 || r.status >= 300) throw new Error(`上游 ${r.status}`);
  return JSON.parse(r.body.toString("utf8")) as T;
}
