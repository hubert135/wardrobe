import { describe, expect, it } from "vitest";
import { AIUnavailableError } from "../src/ai/client.js";
import { buildProductPhotoPrompt } from "../src/ai/productPhoto.js";
import { RenderProductPhotoResponseSchema } from "../src/schemas/render.js";
import { devSession, FakeAI, FakeRenderer, fakeImage, makeApp, post } from "./helpers.js";

const hints = { name: "Fair Isle crew neck", category: "sweater", subcategory: "crew neck sweater", primaryColor: "black", secondaryColor: "green", pattern: "patterned", material: "lambswool" };

describe("POST /v1/garments/render", () => {
  it("returns a store-style photo and passes the garment hints to the renderer", async () => {
    const renderer = new FakeRenderer();
    const app = makeApp(new FakeAI(), {}, undefined, renderer);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/render", { image: fakeImage, garment: hints }, token);
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(RenderProductPhotoResponseSchema.safeParse(body).success).toBe(true);
    expect(renderer.calls[0]!.garment).toMatchObject({ category: "sweater", primaryColor: "black" });
  });

  it("works without garment hints and without a Claude key", async () => {
    const renderer = new FakeRenderer();
    const app = makeApp(null, {}, undefined, renderer);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/render", { image: fakeImage }, token);
    expect(response.status).toBe(200);
    expect(renderer.calls[0]!.garment).toBeNull();
  });

  it("returns 503 when no image provider is configured", async () => {
    const app = makeApp(new FakeAI(), {}, undefined, null);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/render", { image: fakeImage }, token);
    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("ai_not_configured");
  });

  it("maps provider outages to 503 ai_unavailable", async () => {
    const renderer = { render: async () => { throw new AIUnavailableError("down", true); } };
    const app = makeApp(new FakeAI(), {}, undefined, renderer);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/render", { image: fakeImage }, token);
    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("ai_unavailable");
  });

  it("has its own stricter rate limit", async () => {
    const app = makeApp(new FakeAI(), { RENDER_RATE_LIMIT_REQUESTS: "1", RATE_LIMIT_REQUESTS: "50" }, undefined, new FakeRenderer());
    const token = await devSession(app);
    const first = await post(app, "/v1/garments/render", { image: fakeImage }, token);
    const second = await post(app, "/v1/garments/render", { image: fakeImage }, token);
    expect([first.status, second.status]).toEqual([200, 429]);
  });

  it("requires a session", async () => {
    const app = makeApp(new FakeAI(), {}, undefined, new FakeRenderer());
    expect((await post(app, "/v1/garments/render", { image: fakeImage })).status).toBe(401);
  });
});

describe("Claude endpoints without an Anthropic key", () => {
  it("return 503 ai_not_configured", async () => {
    const app = makeApp(null);
    const token = await devSession(app);
    const response = await post(app, "/v1/garments/analyze", { image: fakeImage }, token);
    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("ai_not_configured");
  });
});

describe("product photo prompt", () => {
  it("describes the garment and insists on fidelity and a white background", () => {
    const prompt = buildProductPhotoPrompt(hints as never);
    expect(prompt).toContain("black with green patterned lambswool crew neck sweater");
    expect(prompt).toContain("Fair Isle crew neck");
    expect(prompt).toMatch(/do not change the color/i);
    expect(prompt).toMatch(/white seamless background/i);
    expect(prompt).toMatch(/no hanger/i);
  });

  it("still works without hints", () => {
    const prompt = buildProductPhotoPrompt(null);
    expect(prompt).not.toContain("The item is a");
    expect(prompt).toMatch(/ghost mannequin/i);
  });
});
