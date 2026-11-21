import { getDb } from "../db";
import { PlannerStore } from "./store";

export function getPlanner() {
  return new PlannerStore(getDb());
}

const runtime = globalThis as typeof globalThis & { plannerArchiveTimer?: NodeJS.Timeout };

export function startPlannerArchiveLoop() {
  if (runtime.plannerArchiveTimer) return;
  const sweep = () => {
    try {
      getPlanner().sweep();
    } catch (error) {
      console.error("规划归档检查失败", error);
    }
  };
  sweep();
  runtime.plannerArchiveTimer = setInterval(sweep, 60_000).unref();
}
