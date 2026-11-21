// Start the two independent maintenance loops in the Node server process.
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const [{ startCampusSyncLoop }, { startPlannerArchiveLoop }] = await Promise.all([
      import("@/lib/campus-sync"),
      import("@/lib/planner/server"),
    ]);
    startCampusSyncLoop();
    startPlannerArchiveLoop();
  }
}
