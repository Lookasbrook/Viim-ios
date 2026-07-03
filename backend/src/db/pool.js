import pg from "pg";
import { config } from "../config.js";

const { Pool } = pg;

export const pool = config.databaseUrl
  ? new Pool({
      connectionString: config.databaseUrl,
      max: 5,
      idleTimeoutMillis: 10_000
    })
  : null;

export async function checkDatabase() {
  if (!pool) {
    return { status: "not_configured" };
  }

  const result = await pool.query("SELECT 1 AS ok");
  return { status: result.rows[0]?.ok === 1 ? "ok" : "error" };
}
