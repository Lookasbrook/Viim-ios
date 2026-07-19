import assert from "node:assert/strict";
import { test } from "node:test";
import { runMigrations } from "../src/db/migrate.js";

test("runMigrations applies SQL migrations", async () => {
  const queries = [];

  await runMigrations({
    database: {
      async query(sql) {
        queries.push(sql);
      }
    },
    logger: {
      info() {}
    }
  });

  assert.ok(queries.length > 0);
  assert.match(queries.join("\n"), /CREATE TABLE IF NOT EXISTS alerts/);
  assert.match(queries.join("\n"), /provider_message_id/);
});

test("runMigrations requires a database", async () => {
  await assert.rejects(
    () => runMigrations({ database: null }),
    /database_not_configured/
  );
});
