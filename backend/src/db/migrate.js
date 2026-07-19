import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { pool } from "./pool.js";

const migrationsDirectory = join(dirname(fileURLToPath(import.meta.url)), "migrations");

export async function runMigrations({ database = pool, logger = console } = {}) {
  if (!database) {
    throw new Error("database_not_configured");
  }

  const files = (await readdir(migrationsDirectory))
    .filter((file) => file.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const sql = await readFile(join(migrationsDirectory, file), "utf8");
    await database.query(sql);
    logger.info("db.migration.applied", { file });
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runMigrations()
    .catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    })
    .finally(async () => {
      await pool?.end();
    });
}
