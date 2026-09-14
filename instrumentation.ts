// Next.js instrumentation：服务启动时启动校园事务自动同步
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const { startCampusSyncLoop } = await import("@/lib/campus-sync");
    startCampusSyncLoop();
  }
}
