import { AnthropicAIClient } from "./ai/client.js";
import { OpenAIProductPhotoRenderer } from "./ai/productPhoto.js";
import { createApp } from "./app.js";
import { loadConfig, type Env } from "./config.js";

/** Builds the production app from environment variables (Node, Workers, Vercel). */
export function createAppFromEnv(env: Env) {
  const config = loadConfig(env);
  const ai = config.anthropicApiKey
    ? new AnthropicAIClient({ apiKey: config.anthropicApiKey, model: config.aiModel, effort: config.aiEffort })
    : null;
  const renderer = config.openaiApiKey
    ? new OpenAIProductPhotoRenderer({ apiKey: config.openaiApiKey, model: config.imageModel, quality: config.imageQuality })
    : null;
  return createApp({ config, ai, renderer });
}

/** One line per feature so it's obvious at startup what this server can do. */
export function describeFeatures(env: Env): string[] {
  const config = loadConfig(env);
  return [
    `Recognition, order import, outfit ranking (Claude ${config.aiModel}): ${config.anthropicApiKey ? "on" : "off - set ANTHROPIC_API_KEY"}`,
    `Store-style photos (OpenAI ${config.imageModel}, ${config.imageQuality} quality): ${config.openaiApiKey ? "on" : "off - set OPENAI_API_KEY"}`,
    `Development sign-in: ${config.authDevBypass ? "on" : "off"}`,
  ];
}
