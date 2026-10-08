// Cloudflare Workers entry point. Configure secrets with `wrangler secret put ANTHROPIC_API_KEY` etc.
import { createAppFromEnv } from "./env.js";

type WorkerApp = ReturnType<typeof createAppFromEnv>;
let app: WorkerApp | undefined;

export default {
  fetch(request: Request, env: Record<string, string | undefined>, ctx: unknown) {
    app ??= createAppFromEnv(env);
    return app.fetch(request, env, ctx as never);
  },
};
