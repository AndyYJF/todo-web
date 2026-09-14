"use client";

import { useState } from "react";
import { motion } from "motion/react";

export default function LoginPage() {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [shake, setShake] = useState(0);
  const [loading, setLoading] = useState(false);

  async function submit() {
    if (!password || loading) return;
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ password }),
      });
      if (res.ok) {
        window.location.href = "/";
        return;
      }
      setError("密码错误，再试一次");
      setShake((s) => s + 1);
      setPassword("");
    } catch {
      setError("网络异常，请重试");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen grid place-items-center px-6">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 300, damping: 30 }}
        className="w-full max-w-sm"
      >
        <div className="text-center mb-8">
          <div className="font-display text-[44px] leading-none tracking-tight">
            Todo<span className="text-accent">.</span>
          </div>
          <div className="mt-3 text-[10px] uppercase tracking-[0.28em] text-ink-soft">
            Private Access
          </div>
        </div>

        <motion.div
          key={shake}
          animate={shake ? { x: [0, -10, 10, -7, 7, -3, 0] } : undefined}
          transition={{ duration: 0.4 }}
          className="bg-card border border-line rounded-2xl shadow-card p-6"
        >
          <label className="block text-[10px] uppercase tracking-[0.18em] text-ink-soft mb-2">
            访问密码
          </label>
          <input
            type="password"
            autoFocus
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && submit()}
            placeholder="输入密码"
            className="w-full bg-paper border border-line rounded-xl px-4 py-3 text-[15px] outline-none focus:border-ink/40 transition-colors"
          />
          {error && (
            <div className="mt-2.5 text-[13px] text-danger">{error}</div>
          )}
          <motion.button
            whileTap={{ scale: 0.97 }}
            onClick={submit}
            disabled={loading || !password}
            className="mt-4 w-full bg-ink text-paper rounded-xl py-3 text-sm font-medium hover:bg-black disabled:opacity-40 transition-colors"
          >
            {loading ? "验证中…" : "进入"}
          </motion.button>
        </motion.div>

        <div className="mt-6 text-center text-[11px] text-ink-soft/60">
          会话保持 30 天
        </div>
      </motion.div>
    </div>
  );
}
