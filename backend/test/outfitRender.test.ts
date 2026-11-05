import { describe, expect, it } from "vitest";
import { buildOutfitPrompt, HOUSE_MODEL_PROMPT } from "../src/ai/outfitPhoto.js";
import { MemoryRenderCache, renderKey } from "../src/ai/renderCache.js";
import { devSession, FakeAI, FakeOutfitRenderer, FakeRenderer, fakeImage, makeApp, post } from "./helpers.js";

const items = [
  { slot: "top", garment: { category: "shirt", subcategory: "oxford shirt", primaryColor: "white", material: "cotton" }, image: fakeImage },
  { slot: "bottom", garment: { category: "chinos", primaryColor: "beige" } },
  { slot: "shoes", garment: { category: "shoes", subcategory: "suede loafers", primaryColor: "brown" }, image: fakeImage },
  { slot: "outerwear", garment: { category: "blazer", subcategory: "unstructured blazer", primaryColor: "navy", material: "wool" } },
];

describe("POST /v1/outfits/render", () => {
  it("dresses the house model in the outfit", async () => {
    const outfits = new FakeOutfitRenderer();
    const app = makeApp(null, {}, undefined, null, { outfitRenderer: outfits });
    const token = await devSession(app);
    const response = await post(app, "/v1/outfits/render", { items }, token);
    expect(response.status).toBe(200);
    expect(((await response.json()) as { image: { mediaType: string } }).image.mediaType).toBe("image/jpeg");
    expect(outfits.calls[0]!.model).toBe("house");
    expect(outfits.calls[0]!.items).toHaveLength(4);
    expect(outfits.calls[0]!.items.find((item) => item.slot === "bottom")!.image).toBeNull();
  });

  it("rejects outfits with two garments in one slot or too few pieces", async () => {
    const app = makeApp(null, {}, undefined, null, { outfitRenderer: new FakeOutfitRenderer() });
    const token = await devSession(app);
    expect((await post(app, "/v1/outfits/render", { items: [items[0], items[0]] }, token)).status).toBe(400);
    expect((await post(app, "/v1/outfits/render", { items: [items[0]] }, token)).status).toBe(400);
  });

  it("returns 503 when no image provider is configured", async () => {
    const app = makeApp(null);
    const token = await devSession(app);
    const response = await post(app, "/v1/outfits/render", { items }, token);
    expect(response.status).toBe(503);
  });

  it("requires a session", async () => {
    const app = makeApp(null, {}, undefined, null, { outfitRenderer: new FakeOutfitRenderer() });
    expect((await post(app, "/v1/outfits/render", { items })).status).toBe(401);
  });
});

describe("render cache", () => {
  it("never pays twice for the same outfit, unless asked for a fresh one", async () => {
    const outfits = new FakeOutfitRenderer();
    const app = makeApp(null, { RATE_LIMIT_REQUESTS: "50" }, undefined, null, { outfitRenderer: outfits, renderCache: new MemoryRenderCache() });
    const token = await devSession(app);
    await post(app, "/v1/outfits/render", { items }, token);
    const reordered = [...items].reverse();
    expect((await post(app, "/v1/outfits/render", { items }, token)).status).toBe(200);
    expect(outfits.calls).toHaveLength(1);
    await post(app, "/v1/outfits/render", { items: reordered, fresh: true }, token);
    expect(outfits.calls).toHaveLength(2);
  });

  it("caches product photos too", async () => {
    const renderer = new FakeRenderer();
    const app = makeApp(null, { RATE_LIMIT_REQUESTS: "50" }, undefined, renderer, { renderCache: new MemoryRenderCache() });
    const token = await devSession(app);
    const garment = { category: "shirt", primaryColor: "white", subcategory: "oxford shirt" };
    await post(app, "/v1/garments/render", { garment }, token);
    await post(app, "/v1/garments/render", { garment }, token);
    expect(renderer.calls).toHaveLength(1);
  });

  it("keys do not depend on property order", async () => {
    expect(await renderKey("x", { a: 1, b: [1, { c: 2, d: 3 }] })).toBe(await renderKey("x", { b: [1, { d: 3, c: 2 }], a: 1 }));
    expect(await renderKey("x", { a: 1 })).not.toBe(await renderKey("y", { a: 1 }));
  });
});

describe("outfit prompt", () => {
  it("lists the pieces in wearing order and points at their photos", () => {
    const prompt = buildOutfitPrompt(items.map((item) => ({ ...item, image: item.image ?? null })) as never);
    const outer = prompt.indexOf("Outer layer: navy wool unstructured blazer");
    const top = prompt.indexOf("Top: white cotton oxford shirt (exactly as in image 2)");
    const shoes = prompt.indexOf("Shoes: brown suede loafers (exactly as in image 3)");
    expect(outer).toBeGreaterThan(-1);
    expect(top).toBeGreaterThan(outer);
    expect(shoes).toBeGreaterThan(top);
    expect(prompt).toContain("Bottoms: beige chinos");
    expect(prompt).toMatch(/no logos, brand names/i);
    expect(prompt).toMatch(/same face/i);
    expect(prompt).toMatch(/head to shoes/i);
  });

  it("describes a neutral, logo-free house model", () => {
    expect(HOUSE_MODEL_PROMPT).toMatch(/full-length/i);
    expect(HOUSE_MODEL_PROMPT).toMatch(/without logos/i);
  });
});
