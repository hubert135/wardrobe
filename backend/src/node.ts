import { serve } from "@hono/node-server";
import { createAppFromEnv } from "./env.js";

try {
  process.loadEnvFile?.(".env");
} catch {
  // No .env file: rely on the real environment.
}

const app = createAppFromEnv(process.env);
const port = Number(process.env.PORT ?? 8787);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`Wardrobe backend listening on http://localhost:${info.port}`);
});
