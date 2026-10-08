import { describe, expect, it } from "vitest";
import { ImagePayloadSchema } from "../src/schemas/common.js";
import { AnalyzeGarmentResponseSchema, normalizeAnalysis } from "../src/schemas/garments.js";
import { normalizeOrder, ParseOrderRequestSchema, ParseOrderResponseSchema } from "../src/schemas/orders.js";
import { normalizeRanking, RankOutfitsRequestSchema, RankOutfitsResponseSchema, type RankOutfitsRequest } from "../src/schemas/outfits.js";
import { sampleGarment } from "./helpers.js";

describe("garment analysis", () => {
  it("clamps formality and confidence and drops duplicate secondary colors", () => {
    const result = normalizeAnalysis({
      garments: [{ ...sampleGarment, formality: 9.4, confidence: 1.7, secondaryColor: "navy", seasons: ["autumn", "autumn"] }],
    });
    expect(result).not.toBeNull();
    const garment = result!.garments[0]!;
    expect(garment.formality).toBe(5);
    expect(garment.confidence).toBe(1);
    expect(garment.secondaryColor).toBeNull();
    expect(garment.seasons).toEqual(["autumn"]);
    expect(AnalyzeGarmentResponseSchema.safeParse(result).success).toBe(true);
  });

  it("drops low-confidence 'other' items and caps the list at 10", () => {
    const garments = Array.from({ length: 14 }, () => ({ ...sampleGarment }));
    garments.push({ ...sampleGarment, category: "other", confidence: 0.1 });
    const result = normalizeAnalysis({ garments } as never);
    expect(result!.garments).toHaveLength(10);
    expect(result!.garments.every((g) => g.category === "shirt")).toBe(true);
  });

  it("allows an empty result (no garment in the photo)", () => {
    expect(normalizeAnalysis({ garments: [] })).toEqual({ garments: [] });
  });
});

describe("image payload", () => {
  it("rejects non-base64 and oversized data", () => {
    expect(ImagePayloadSchema.safeParse({ mediaType: "image/jpeg", data: "not base64 !!!".repeat(20) }).success).toBe(false);
    expect(ImagePayloadSchema.safeParse({ mediaType: "image/jpeg", data: "A".repeat(6_000_000) }).success).toBe(false);
    expect(ImagePayloadSchema.safeParse({ mediaType: "image/tiff", data: "A".repeat(400) }).success).toBe(false);
  });
});

describe("order parsing", () => {
  const text = "Order #123 from 14 Sep 2026. Slim chinos, beige, size 32, 59.90 EUR. Image: https://cdn.shop.example/chinos.jpg";

  it("requires text or a screenshot", () => {
    expect(ParseOrderRequestSchema.safeParse({}).success).toBe(false);
    expect(ParseOrderRequestSchema.safeParse({ text: "too short" }).success).toBe(false);
    expect(ParseOrderRequestSchema.safeParse({ text }).success).toBe(true);
  });

  it("keeps only image URLs that literally appear in the input", () => {
    const result = normalizeOrder(
      {
        isClothingOrder: true,
        items: [
          { name: "Slim chinos", brand: "COS", category: "chinos", color: "beige", size: "32", price: 59.9, currency: "eur", purchaseDate: "2026-09-14", imageUrl: "https://cdn.shop.example/chinos.jpg" },
          { name: "Belt", brand: null, category: "accessory", color: null, size: null, price: -3, currency: "euro", purchaseDate: "14.09.2026", imageUrl: "https://invented.example/belt.jpg" },
        ],
      },
      text,
    );
    expect(ParseOrderResponseSchema.safeParse(result).success).toBe(true);
    expect(result!.items[0]).toMatchObject({ currency: "EUR", imageUrl: "https://cdn.shop.example/chinos.jpg", purchaseDate: "2026-09-14" });
    expect(result!.items[1]).toMatchObject({ price: null, currency: null, purchaseDate: null, imageUrl: null });
  });

  it("never returns image URLs for screenshots", () => {
    const result = normalizeOrder(
      { isClothingOrder: true, items: [{ name: "Tee", brand: null, category: "t-shirt", color: "white", size: "M", price: 15, currency: "EUR", purchaseDate: null, imageUrl: "https://x.example/t.jpg" }] },
      null,
    );
    expect(result!.items[0]!.imageUrl).toBeNull();
  });

  it("returns no items for non-clothing orders", () => {
    expect(normalizeOrder({ isClothingOrder: false, items: [] }, text)).toEqual({ items: [] });
  });
});

describe("outfit ranking", () => {
  const request: RankOutfitsRequest = {
    context: { occasion: "work", style: "smart_casual", season: "autumn", weather: null, preferences: { preferredStyles: ["smart_casual"], favoriteColors: [], avoidedColors: [] } },
    garments: [
      { id: "g1", category: "shirt", subcategory: "", primaryColor: "white", pattern: "solid", material: "", formality: 3 },
      { id: "g2", category: "chinos", subcategory: "", primaryColor: "beige", pattern: "solid", material: "", formality: 3 },
      { id: "g3", category: "shoes", subcategory: "", primaryColor: "brown", pattern: "solid", material: "", formality: 3 },
      { id: "g4", category: "polo", subcategory: "", primaryColor: "navy", pattern: "solid", material: "", formality: 3 },
    ],
    candidates: [
      { id: "c1", garmentIds: ["g1", "g2", "g3"] },
      { id: "c2", garmentIds: ["g4", "g2", "g3"] },
    ],
    count: 3,
  };

  it("rejects candidates that reference unknown garments", () => {
    const bad = { ...request, candidates: [{ id: "c1", garmentIds: ["g1", "gX", "g3"] }] };
    expect(RankOutfitsRequestSchema.safeParse(bad).success).toBe(false);
    expect(RankOutfitsRequestSchema.safeParse(request).success).toBe(true);
  });

  it("discards invented candidates, removes duplicates and resolves garment ids", () => {
    const result = normalizeRanking(
      {
        outfits: [
          { candidateId: "c7", title: "Invented", reasoning: "Not a real candidate." },
          { candidateId: "c2", title: "Polo day", reasoning: "Navy and beige is a classic autumn base." },
          { candidateId: "c2", title: "Again", reasoning: "Duplicate." },
          { candidateId: "c1", title: "  Crisp   white ", reasoning: "White and beige keep it light." },
        ],
      },
      request,
    );
    expect(RankOutfitsResponseSchema.safeParse(result).success).toBe(true);
    expect(result!.outfits.map((o) => o.candidateId)).toEqual(["c2", "c1"]);
    expect(result!.outfits[0]!.garmentIds).toEqual(["g4", "g2", "g3"]);
    expect(result!.outfits[1]!.title).toBe("Crisp white");
  });

  it("returns null when nothing valid remains", () => {
    expect(normalizeRanking({ outfits: [{ candidateId: "nope", title: "x", reasoning: "y" }] }, request)).toBeNull();
  });

  it("caps the number of outfits at the requested count", () => {
    const result = normalizeRanking(
      { outfits: [{ candidateId: "c1", title: "A", reasoning: "One." }, { candidateId: "c2", title: "B", reasoning: "Two." }] },
      { ...request, count: 1 },
    );
    expect(result!.outfits).toHaveLength(1);
  });
});
