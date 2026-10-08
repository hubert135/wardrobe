import { AnthropicAIClient } from "./ai/client.js";
import { createApp } from "./app.js";
import { loadConfig, type Env } from "./config.js";

/** Builds the production app from environment variables (Node, Workers, Vercel). */
export function createAppFromEnv(env: Env) {
  const config = loadConfig(env);
  const ai = new AnthropicAIClient({ apiKey: config.anthropicApiKey, model: config.aiModel, effort: config.aiEffort });
  return createApp({ config, ai });
}
