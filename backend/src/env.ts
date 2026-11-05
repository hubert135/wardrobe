import { AnthropicAIClient } from "./ai/client.js";
import { OpenAIOutfitRenderer, type ReferenceImageStore } from "./ai/outfitPhoto.js";
import { OpenAIProductPhotoRenderer } from "./ai/productPhoto.js";
import type { RenderCache } from "./ai/renderCache.js";
import { createApp } from "./app.js";
import { loadConfig, type Env } from "./config.js";

/** Builds the production app from environment variables (Node, Workers, Vercel). */
export function createAppFromEnv(
  env: Env,
  options: {
    loadStylebook?: () => Promise<string | null>;
    renderCache?: RenderCache;
    referenceImages?: ReferenceImageStore;
  } = {},
) {
  const config = loadConfig(env);
  const ai = config.anthropicApiKey
    ? new AnthropicAIClient({ apiKey: config.anthropicApiKey, model: config.aiModel, effort: config.aiEffort })
    : null;
  const imageOptions = config.openaiApiKey ? { apiKey: config.openaiApiKey, model: config.imageModel, quality: config.imageQuality } : null;
  const renderer = imageOptions ? new OpenAIProductPhotoRenderer(imageOptions) : null;
  const outfitRenderer = imageOptions ? new OpenAIOutfitRenderer({ ...imageOptions, store: options.referenceImages }) : null;
  return createApp({
    config,
    ai,
    renderer,
    outfitRenderer,
    renderCache: options.renderCache ?? null,
    loadStylebook: options.loadStylebook,
  });
}

/** One line per feature so it's obvious at startup what this server can do. */
export function describeFeatures(env: Env): string[] {
  const config = loadConfig(env);
  return [
    `Recognition, order import, outfit ranking (Claude ${config.aiModel}): ${config.anthropicApiKey ? "on" : "off - set ANTHROPIC_API_KEY"}`,
    `Store-style photos (OpenAI ${config.imageModel}, ${config.imageQuality} quality): ${config.openaiApiKey ? "on" : "off - set OPENAI_API_KEY"}`,
    `Outfits on a model (OpenAI ${config.imageModel}): ${config.openaiApiKey ? "on" : "off - set OPENAI_API_KEY"}`,
    `Automatic device sessions (no sign-in needed): ${config.allowDeviceSessions ? "on" : "off - set ALLOW_DEVICE_SESSIONS=true"}`,
    `Development sign-in: ${config.authDevBypass ? "on" : "off"}`,
  ];
}
