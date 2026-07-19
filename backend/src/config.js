export const config = {
  env: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 3000),
  host: process.env.HOST ?? (process.env.NODE_ENV === "production" ? "0.0.0.0" : "127.0.0.1"),
  databaseUrl: process.env.DATABASE_URL ?? "",
  newagentHealthUrl: process.env.NEWAGENT_HEALTH_URL ?? process.env.NEWAGENT_URL ?? "",
  newagentSendUrl: process.env.NEWAGENT_SEND_URL ?? process.env.NEWAGENT_URL ?? "",
  newagentToken: process.env.NEWAGENT_TOKEN ?? "",
  version: process.env.npm_package_version ?? "0.1.0"
};

export function requireProductionDependency(value) {
  return config.env === "production" ? Boolean(value) : true;
}
