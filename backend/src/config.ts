import type { Effort } from "./ai/client.js";

export type ImageQuality = "low" | "medium" | "high";

export interface Config {
  /** Claude (recognition, order parsing, outfit ranking). Optional: those endpoints return 503 without it. */
  anthropicApiKey: string | null;
  /** Single place to change the model. */
  aiModel: string;
  aiEffort: Effort;
  /** HMAC secret for backend session tokens (min 32 chars). */
  sessionSecret: string;
  sessionTtlDays: number;
  /** Bundle ids accepted as the `aud` of Apple identity tokens. */
  appleAudiences: string[];
  /** Accept the identity token "dev" without Apple verification. Never enable in production. */
  authDevBypass: boolean;
  rateLimit: { requests: number; windowMs: number };
  /** OpenAI image editing for store-style product photos. Optional: the endpoint returns 503 without it. */
  openaiApiKey: string | null;
  imageModel: string;
  imageQuality: ImageQuality;
  /** Product photos are the most expensive call, so they get their own, stricter limit. */
  renderRateLimit: { requests: number; windowMs: number };
  corsOrigins: string[];
}

export type Env = Record<string, string | undefined>;

const EFFORTS: Effort[] = ["low", "medium", "high", "xhigh", "max"];

export function loadConfig(env: Env): Config {
  const missing = ["SESSION_SECRET"].filter((key) => !env[key]);
  if (missing.length) throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  const sessionSecret = env.SESSION_SECRET!;
  if (sessionSecret.length < 32) throw new Error("SESSION_SECRET must be at least 32 characters");

  const effort = (env.AI_EFFORT ?? "low") as Effort;
  if (!EFFORTS.includes(effort)) throw new Error(`AI_EFFORT must be one of ${EFFORTS.join(", ")}`);

  const imageQuality = (env.IMAGE_QUALITY ?? "medium") as ImageQuality;
  if (!["low", "medium", "high"].includes(imageQuality)) throw new Error("IMAGE_QUALITY must be low, medium or high");

  return {
    anthropicApiKey: env.ANTHROPIC_API_KEY || null,
    aiModel: env.AI_MODEL ?? "claude-opus-5-5",
    aiEffort: effort,
    sessionSecret,
    sessionTtlDays: Number(env.SESSION_TTL_DAYS ?? 30),
    appleAudiences: (env.APPLE_BUNDLE_IDS ?? "com.example.wardrobe")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    authDevBypass: env.AUTH_DEV_BYPASS === "true",
    rateLimit: {
      requests: Number(env.RATE_LIMIT_REQUESTS ?? 60),
      windowMs: Number(env.RATE_LIMIT_WINDOW_SECONDS ?? 600) * 1000,
    },
    openaiApiKey: env.OPENAI_API_KEY || null,
    imageModel: env.IMAGE_MODEL ?? "gpt-image-2",
    imageQuality,
    renderRateLimit: {
      requests: Number(env.RENDER_RATE_LIMIT_REQUESTS ?? 30),
      windowMs: Number(env.RENDER_RATE_LIMIT_WINDOW_SECONDS ?? 3600) * 1000,
    },
    corsOrigins: (env.CORS_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean),
  };
}
