import { AIOutputError, type AIClient, type StructuredRequest } from "../src/ai/client.js";
import type { ProductPhotoRenderer } from "../src/ai/productPhoto.js";
import { createApp } from "../src/app.js";
import { loadConfig, type Env } from "../src/config.js";
import type { AIGarmentSchema } from "../src/schemas/garments.js";
import type { z } from "zod";

/** Scripted AI: returns queued outputs in order; an Error entry is thrown instead. */
export class FakeAI implements AIClient {
  readonly calls: StructuredRequest<unknown>[] = [];
  constructor(private readonly queue: unknown[] = []) {}

  push(...outputs: unknown[]) {
    this.queue.push(...outputs);
    return this;
  }

  async generate<T>(request: StructuredRequest<T>): Promise<T> {
    this.calls.push(request as StructuredRequest<unknown>);
    const next = this.queue.shift();
    if (next === undefined) throw new AIOutputError("No scripted output");
    if (next instanceof Error) throw next;
    // Mirror the real client: schema validation happens before the output is returned.
    const parsed = request.schema.safeParse(next);
    if (!parsed.success) throw new AIOutputError("Schema mismatch");
    return parsed.data;
  }
}

export const testEnv: Env = {
  ANTHROPIC_API_KEY: "test-key",
  SESSION_SECRET: "test-secret-test-secret-test-secret-123",
  AUTH_DEV_BYPASS: "true",
  RATE_LIMIT_REQUESTS: "5",
  RATE_LIMIT_WINDOW_SECONDS: "60",
};

export function makeApp(
  ai: AIClient | null,
  overrides: Env = {},
  verifyAppleToken?: (token: string) => Promise<string>,
  renderer: ProductPhotoRenderer | null = null,
) {
  return createApp({ config: loadConfig({ ...testEnv, ...overrides }), ai, verifyAppleToken, renderer });
}

/** Records render calls and returns a fixed JPEG payload. */
export class FakeRenderer implements ProductPhotoRenderer {
  readonly calls: Array<Parameters<ProductPhotoRenderer["render"]>[0]> = [];
  async render(input: Parameters<ProductPhotoRenderer["render"]>[0]) {
    this.calls.push(input);
    return { mediaType: "image/jpeg" as const, data: "B".repeat(200) };
  }
}

export async function devSession(app: ReturnType<typeof makeApp>): Promise<string> {
  const response = await app.request("/v1/auth/session", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ identityToken: "dev" }),
  });
  const body = (await response.json()) as { sessionToken: string };
  return body.sessionToken;
}

export function post(app: ReturnType<typeof makeApp>, path: string, body: unknown, token?: string) {
  return app.request(path, {
    method: "POST",
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
}

/** A tiny but valid-looking base64 payload. */
export const fakeImage = { mediaType: "image/jpeg", data: "A".repeat(400) };

export const sampleGarment: z.infer<typeof AIGarmentSchema> = {
  name: "Navy oxford shirt",
  category: "shirt",
  subcategory: "oxford shirt",
  primaryColor: "navy",
  secondaryColor: null,
  pattern: "solid",
  material: "cotton",
  formality: 4,
  seasons: ["spring", "autumn"],
  brand: null,
  confidence: 0.92,
};
