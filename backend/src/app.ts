import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { z } from "zod";
import { AIOutputError, AIUnavailableError, generateWithRetry, type AIClient } from "./ai/client.js";
import type { ProductPhotoRenderer } from "./ai/productPhoto.js";
import { ANALYZE_GARMENT_SYSTEM, PARSE_ORDER_SYSTEM, RANK_OUTFITS_SYSTEM } from "./ai/prompts.js";
import { appleTokenVerifier, issueSession, verifySession, type AppleTokenVerifier } from "./auth/tokens.js";
import type { Config } from "./config.js";
import { ApiError, errorResponse, parseBody } from "./errors.js";
import { RateLimiter, rateLimit } from "./middleware/rateLimit.js";
import { AIAnalyzeOutputSchema, AnalyzeGarmentRequestSchema, normalizeAnalysis } from "./schemas/garments.js";
import { AIOrderOutputSchema, normalizeOrder, ParseOrderRequestSchema } from "./schemas/orders.js";
import { AIRankOutputSchema, normalizeRanking, RankOutfitsRequestSchema } from "./schemas/outfits.js";
import { RenderProductPhotoRequestSchema } from "./schemas/render.js";

export interface AppDependencies {
  config: Config;
  /** Claude client; null when ANTHROPIC_API_KEY is not set. */
  ai: AIClient | null;
  /** Image editing for store-style photos; null when OPENAI_API_KEY is not set. */
  renderer?: ProductPhotoRenderer | null;
  /** Injected in tests; defaults to verification against Apple's public keys. */
  verifyAppleToken?: AppleTokenVerifier;
  now?: () => number;
}

type Env = { Variables: { userId: string } };

const SessionRequestSchema = z.object({ identityToken: z.string().min(1).max(10_000) });

/** ISO-8601 without milliseconds (what Swift's `.iso8601` decoder expects). */
const isoSeconds = (date: Date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");

function clientIP(c: Context): string {
  return c.req.header("cf-connecting-ip") ?? c.req.header("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
}

export function createApp(deps: AppDependencies) {
  const { config } = deps;
  const renderer = deps.renderer ?? null;
  const notConfigured = (what: string) =>
    new ApiError(503, "ai_not_configured", `${what} is not set up on this server yet.`);
  /** Claude client or a clean 503 when the server has no Anthropic key. */
  const claude = (): AIClient => {
    if (!deps.ai) throw notConfigured("Automatic recognition");
    return deps.ai;
  };
  const now = deps.now ?? Date.now;
  const verifyAppleToken = deps.verifyAppleToken ?? appleTokenVerifier(config.appleAudiences);
  const app = new Hono<Env>();

  if (config.corsOrigins.length) app.use("*", cors({ origin: config.corsOrigins }));

  app.use(
    "/v1/*",
    bodyLimit({
      maxSize: 6 * 1024 * 1024,
      onError: (c) => errorResponse(c, new ApiError(413, "payload_too_large", "The upload is too large. Use a smaller photo.")),
    }),
  );

  app.get("/health", (c) => c.json({ status: "ok" }));

  // ---- Auth ----

  const sessionLimiter = new RateLimiter(20, 10 * 60 * 1000, now);

  app.post("/v1/auth/session", rateLimit(sessionLimiter, clientIP), async (c) => {
    const { identityToken } = await parseBody(c, SessionRequestSchema);
    let userId: string;
    if (config.authDevBypass && identityToken === "dev") {
      userId = "dev-user";
    } else {
      try {
        userId = await verifyAppleToken(identityToken);
      } catch {
        throw new ApiError(401, "invalid_identity_token", "Sign in with Apple could not be verified. Please try again.");
      }
    }
    const session = await issueSession(userId, config.sessionSecret, config.sessionTtlDays, new Date(now()));
    return c.json({ sessionToken: session.token, userId, expiresAt: isoSeconds(session.expiresAt) });
  });

  // ---- Protected AI endpoints ----

  const requireSession = async (c: Context<Env>, next: () => Promise<void>) => {
    const header = c.req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) throw new ApiError(401, "unauthorized", "Sign in to use this feature.");
    try {
      c.set("userId", await verifySession(token, config.sessionSecret));
    } catch {
      throw new ApiError(401, "unauthorized", "Your session has expired. Please sign in again.");
    }
    await next();
  };

  const aiLimiter = new RateLimiter(config.rateLimit.requests, config.rateLimit.windowMs, now);
  for (const path of ["/v1/garments/*", "/v1/orders/*", "/v1/outfits/*"]) {
    app.use(path, requireSession, rateLimit(aiLimiter, (c) => (c as Context<Env>).get("userId")));
  }

  app.post("/v1/garments/analyze", async (c) => {
    const body = await parseBody(c, AnalyzeGarmentRequestSchema);
    const result = await generateWithRetry(
      claude(),
      {
        task: "garments.analyze",
        system: ANALYZE_GARMENT_SYSTEM,
        content: [
          { type: "image", image: body.image },
          { type: "text", text: "Catalogue the garments in this photo." },
        ],
        schema: AIAnalyzeOutputSchema,
        maxTokens: 4_000,
      },
      normalizeAnalysis,
    );
    if (result.garments.length === 0) {
      throw new ApiError(422, "no_garment_found", "No clothing was found in this photo. Try a clearer shot on a plain background.");
    }
    return c.json(result);
  });

  const renderLimiter = new RateLimiter(config.renderRateLimit.requests, config.renderRateLimit.windowMs, now);

  app.post(
    "/v1/garments/render",
    rateLimit(renderLimiter, (c) => `render:${(c as Context<Env>).get("userId")}`),
    async (c) => {
      if (!renderer) throw notConfigured("Store-style photos");
      const body = await parseBody(c, RenderProductPhotoRequestSchema);
      const image = await renderer.render({ image: body.image, garment: body.garment ?? null });
      return c.json({ image });
    },
  );

  app.post("/v1/orders/parse", async (c) => {
    const body = await parseBody(c, ParseOrderRequestSchema);
    const text = body.text?.trim() || null;
    const content = body.image
      ? [
          { type: "image" as const, image: body.image },
          { type: "text" as const, text: "Extract the purchased items from this order screenshot." },
        ]
      : [{ type: "text" as const, text: `Order confirmation:\n\n${text ?? ""}` }];
    const result = await generateWithRetry(
      claude(),
      { task: "orders.parse", system: PARSE_ORDER_SYSTEM, content, schema: AIOrderOutputSchema, maxTokens: 8_000 },
      (raw) => normalizeOrder(raw, body.image ? null : text),
    );
    return c.json(result);
  });

  app.post("/v1/outfits/rank", async (c) => {
    const body = await parseBody(c, RankOutfitsRequestSchema);
    const input = JSON.stringify({ context: body.context, garments: body.garments, candidates: body.candidates });
    const result = await generateWithRetry(
      claude(),
      {
        task: "outfits.rank",
        system: RANK_OUTFITS_SYSTEM,
        content: [{ type: "text", text: `Choose the best ${body.count} outfits.\n\n${input}` }],
        schema: AIRankOutputSchema,
        maxTokens: 4_000,
      },
      (raw) => normalizeRanking(raw, body),
    );
    return c.json(result);
  });

  // ---- Errors ----

  app.notFound((c) => errorResponse(c, new ApiError(404, "not_found", "Not found.")));

  app.onError((error, c) => {
    if (error instanceof ApiError) return errorResponse(c, error);
    if (error instanceof AIOutputError) {
      console.warn(JSON.stringify({ level: "warn", event: "ai_invalid_output", path: c.req.path, message: error.message }));
      return errorResponse(c, new ApiError(502, "ai_invalid_output", "The AI could not produce a valid answer. Please try again."));
    }
    if (error instanceof AIUnavailableError) {
      console.error(JSON.stringify({ level: "error", event: "ai_unavailable", path: c.req.path, message: error.message }));
      return errorResponse(c, new ApiError(503, "ai_unavailable", "The AI service is temporarily unavailable. Please try again soon."));
    }
    console.error(JSON.stringify({ level: "error", event: "unhandled", path: c.req.path, message: String(error) }));
    return errorResponse(c, new ApiError(500, "internal_error", "Something went wrong on our side."));
  });

  return app;
}
