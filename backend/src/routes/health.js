import { Router } from "express";
import { config, requireProductionDependency } from "../config.js";
import { checkDatabase } from "../db/pool.js";
import { checkNewagent } from "../services/newagent.js";

export const healthRouter = Router();

healthRouter.get("/", async (_request, response) => {
  const [db, whatsapp] = await Promise.allSettled([
    checkDatabase(),
    checkNewagent()
  ]);

  const dbStatus = db.status === "fulfilled" ? db.value : { status: "error" };
  const whatsappStatus = whatsapp.status === "fulfilled" ? whatsapp.value : { status: "error" };
  const dependenciesConfigured =
    requireProductionDependency(config.databaseUrl) &&
    requireProductionDependency(config.newagentUrl) &&
    requireProductionDependency(config.newagentToken);
  const dependencyErrors = [dbStatus.status, whatsappStatus.status].includes("error");
  const status = dependenciesConfigured && !dependencyErrors ? "ok" : "degraded";

  response.status(config.env === "production" && status !== "ok" ? 503 : 200).json({
    status,
    api: "ok",
    db: dbStatus.status,
    whatsapp: whatsappStatus.status,
    version: config.version
  });
});
