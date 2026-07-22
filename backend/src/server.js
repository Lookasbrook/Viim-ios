import express from "express";
import { config } from "./config.js";
import { logScrubber } from "./middleware/logScrubber.js";
import { createAlertsRouter } from "./routes/alerts.js";
import { createCircleRouter, createJoinRouter } from "./routes/circle.js";
import { healthRouter } from "./routes/health.js";

const app = express();

app.disable("x-powered-by");
app.use(express.json({ limit: "256kb" }));
app.use(logScrubber);

app.use("/health", healthRouter);
app.use("/v1/health", healthRouter);
app.use("/v1/alerts", createAlertsRouter());
app.use("/v1/circle", createCircleRouter());
app.use("/join", createJoinRouter());

app.use((_request, response) => {
  response.status(404).json({ error: "not_found" });
});

const server = app.listen(config.port, config.host, () => {
  console.info(`viim-api listening on ${config.host}:${config.port}`);
});

server.on("error", (error) => {
  console.error(error);
  process.exitCode = 1;
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    server.close(() => {
      process.exit(0);
    });
  });
}
