import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { logger } from "hono/logger";
import { createAppFromEnv, describeFeatures } from "./env.js";

try {
  process.loadEnvFile?.(".env");
} catch {
  // No .env file: rely on the real environment.
}

// Local server: print each request (method, path, status, time) so connection problems are easy to spot.
const app = new Hono();
app.use("*", logger());
app.route("/", createAppFromEnv(process.env));
const port = Number(process.env.PORT ?? 8787);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`Wardrobe backend listening on http://localhost:${info.port}`);
  for (const line of describeFeatures(process.env)) console.log(`  ${line}`);
});
