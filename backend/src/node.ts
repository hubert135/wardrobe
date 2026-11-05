import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { logger } from "hono/logger";
import { createAppFromEnv, describeFeatures } from "./env.js";
import { FileReferenceStore, FileRenderCache } from "./fileStores.js";

try {
  process.loadEnvFile?.(".env");
} catch {
  // No .env file: rely on the real environment.
}

// Local server: print each request (method, path, status, time) so connection problems are easy to spot.
const app = new Hono();
app.use("*", logger());
const stylebookPath = process.env.STYLEBOOK_PATH ?? "data/stylebook.json";
const loadStylebook = () => readFile(stylebookPath, "utf8").catch(() => null);
// Generated images live next to the style guide in data/ (git-ignored).
const dataDir = dirname(stylebookPath);
const renderCache = new FileRenderCache(join(dataDir, "render-cache"));
const referenceImages = new FileReferenceStore(join(dataDir, "models"));
app.route("/", createAppFromEnv(process.env, { loadStylebook, renderCache, referenceImages }));
const port = Number(process.env.PORT ?? 8787);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`Wardrobe backend listening on http://localhost:${info.port}`);
  for (const line of describeFeatures(process.env)) console.log(`  ${line}`);
  loadStylebook().then((json) =>
    console.log(`  Style guide: ${json ? `${JSON.parse(json).recipes.length} recipes from ${stylebookPath}` : "none (see tools/stylebook)"}`),
  );
});
