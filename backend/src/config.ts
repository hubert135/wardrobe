import type { Effort } from "./ai/client.js";

export interface Config {
  anthropicApiKey: string;
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
  corsOrigins: string[];
}

export type Env = Record<string, string | undefined>;

const EFFORTS: Effort[] = ["low", "medium", "high", "xhigh", "max"];

export function loadConfig(env: Env): Config {
  const missing = ["ANTHROPIC_API_KEY", "SESSION_SECRET"].filter((key) => !env[key]);
  if (missing.length) throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  const sessionSecret = env.SESSION_SECRET!;
  if (sessionSecret.length < 32) throw new Error("SESSION_SECRET must be at least 32 characters");

  const effort = (env.AI_EFFORT ?? "low") as Effort;
  if (!EFFORTS.includes(effort)) throw new Error(`AI_EFFORT must be one of ${EFFORTS.join(", ")}`);

  return {
    anthropicApiKey: env.ANTHROPIC_API_KEY!,
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
    corsOrigins: (env.CORS_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean),
  };
}
