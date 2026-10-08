import { describe, expect, it } from "vitest";
import { AIOutputError, AIUnavailableError } from "../src/ai/client.js";
import { RateLimiter } from "../src/middleware/rateLimit.js";
import { devSession, FakeAI, fakeImage, makeApp, post, sampleGarment } from "./helpers.js";

describe("auth", () => {
  it("issues a session for the dev token when bypass is enabled", async () => {
    const app = makeApp(new FakeAI());
    const response = await post(app, "/v1/auth/session", { identityToken: "dev" });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { sessionToken: string; userId: string; expiresAt: string };
    expect(body.userId).toBe("dev-user");
    expect(body.expiresAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  });

  it("rejects the dev token when bypass is disabled", async () => {
    const app = makeApp(new FakeAI(), { AUTH_DEV_BYPASS: "false" }, async () => {
      throw new Error("bad token");
    });
    const response = await post(app, "/v1/auth/session", { identityToken: "dev" });
    expect(response.status).toBe(401);
  });

  it("uses the Apple subject as the user id", async () => {
    const app = makeApp(new FakeAI(), { AUTH_DEV_BYPASS: "false" }, async (token) => `apple-${token.length}`);
    const response = await post(app, "/v1/auth/session", { identityToken: "header.payload.signature" });
    expect(((await response.json()) as { userId: string }).userId).toBe("apple-24");
  });

  it("requires a session on AI endpoints", async () => {
    const app = makeApp(new FakeAI());
    expect((await post(app, "/v1/garments/analyze", { image: fakeImage })).status).toBe(401);
    expect((await post(app, "/v1/garments/analyze", { image: fakeImage }, "garbage")).status).toBe(401);
  });
});

describe("POST /v1/garments/analyze", () => {
  it("returns normalized garments", async () => {
    const ai = new FakeAI([{ garments: [{ ...sampleGarment, formality: 7 }] }]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { garments: Array<{ formality: number; name: string }> };
    expect(body.garments[0]).toMatchObject({ name: "Navy oxford shirt", formality: 5 });
    expect(ai.calls[0]!.content[0]!.type).toBe("image");
  });

  it("retries once on invalid output and then succeeds", async () => {
    const ai = new FakeAI([{ garments: "not an array" }, { garments: [sampleGarment] }]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(200);
    expect(ai.calls).toHaveLength(2);
  });

  it("returns a clean 502 after two invalid outputs", async () => {
    const ai = new FakeAI([new AIOutputError("refusal"), { wrong: true }, { garments: [sampleGarment] }]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: { code: "ai_invalid_output", message: expect.any(String) } });
    expect(ai.calls).toHaveLength(2);
  });

  it("does not retry when the provider is unavailable", async () => {
    const ai = new FakeAI([new AIUnavailableError("down", true)]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(503);
    expect(ai.calls).toHaveLength(1);
  });

  it("returns 422 when no garment is found", async () => {
    const app = makeApp(new FakeAI([{ garments: [] }]));
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(422);
  });

  it("validates the request body", async () => {
    const app = makeApp(new FakeAI());
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: { mediaType: "image/jpeg" } }, token);
    expect(response.status).toBe(400);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("invalid_request");
  });
});

describe("POST /v1/orders/parse", () => {
  it("extracts items from order text", async () => {
    const ai = new FakeAI([
      {
        isClothingOrder: true,
        items: [{ name: "Slim chinos", brand: "COS", category: "chinos", color: "beige", size: "32", price: 59.9, currency: "EUR", purchaseDate: "2026-09-14", imageUrl: null }],
      },
    ]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/orders/parse", { text: "Thank you for your order! Slim chinos beige 32 — 59,90 €" }, token);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { items: unknown[] };
    expect(body.items).toHaveLength(1);
  });
});

describe("POST /v1/outfits/rank", () => {
  const rankRequest = {
    context: { occasion: "work", style: "smart_casual", season: "autumn", weather: { temperatureC: 8, feelsLikeC: 6, precipitationChance: 0.6, windKph: 20 }, preferences: { preferredStyles: ["smart_casual"], favoriteColors: ["navy"], avoidedColors: [] } },
    garments: [
      { id: "g1", category: "shirt", subcategory: "", primaryColor: "white", pattern: "solid", material: "", formality: 3 },
      { id: "g2", category: "chinos", subcategory: "", primaryColor: "beige", pattern: "solid", material: "", formality: 3 },
      { id: "g3", category: "shoes", subcategory: "", primaryColor: "brown", pattern: "solid", material: "", formality: 3 },
      { id: "g4", category: "coat", subcategory: "", primaryColor: "navy", pattern: "solid", material: "wool", formality: 4 },
    ],
    candidates: [{ id: "c1", garmentIds: ["g4", "g1", "g2", "g3"] }],
    count: 3,
  };

  it("returns ranked outfits with resolved garment ids", async () => {
    const ai = new FakeAI([{ outfits: [{ candidateId: "c1", title: "Navy coat classic", reasoning: "The navy coat handles the rain over a crisp white and beige base." }] }]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/outfits/rank", rankRequest, token);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { outfits: Array<{ garmentIds: string[] }> };
    expect(body.outfits[0]!.garmentIds).toEqual(["g4", "g1", "g2", "g3"]);
    // Only ids and attributes are sent to the model: no images.
    expect(ai.calls[0]!.content.every((block) => block.type === "text")).toBe(true);
  });

  it("retries when the model only returns unknown candidates", async () => {
    const ai = new FakeAI([
      { outfits: [{ candidateId: "c99", title: "Invented", reasoning: "Nope." }] },
      { outfits: [{ candidateId: "c1", title: "Real", reasoning: "Works." }] },
    ]);
    const app = makeApp(ai);
    const token = await devSession(app);
    const response = await post(app, "/v1/outfits/rank", rankRequest, token);
    expect(response.status).toBe(200);
    expect(ai.calls).toHaveLength(2);
  });
});

describe("rate limiting", () => {
  it("limits AI requests per user", async () => {
    const outputs = Array.from({ length: 10 }, () => ({ garments: [sampleGarment] }));
    const app = makeApp(new FakeAI(outputs), { RATE_LIMIT_REQUESTS: "2" });
    const token = await devSession(app);
    const statuses = [];
    for (let i = 0; i < 3; i++) statuses.push((await post(app, "/v1/garments/analyze", { image: fakeImage }, token)).status);
    expect(statuses).toEqual([200, 200, 429]);
  });

  it("resets after the window", () => {
    let now = 0;
    const limiter = new RateLimiter(1, 1000, () => now);
    expect(limiter.check("u").allowed).toBe(true);
    expect(limiter.check("u").allowed).toBe(false);
    expect(limiter.check("other").allowed).toBe(true);
    now = 1000;
    expect(limiter.check("u").allowed).toBe(true);
  });
});

describe("misc", () => {
  it("rejects bodies over the size limit", async () => {
    const app = makeApp(new FakeAI());
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: { mediaType: "image/jpeg", data: "A".repeat(7 * 1024 * 1024) } }, token);
    expect(response.status).toBe(413);
  });

  it("returns JSON 404s", async () => {
    const response = await makeApp(new FakeAI()).request("/nope");
    expect(response.status).toBe(404);
  });
});
