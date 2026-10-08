import { z } from "zod";
import { cleanText } from "./common.js";
import { CATEGORIES, OCCASIONS, PATTERNS, SEASONS, STYLES } from "./taxonomy.js";

export const MAX_CANDIDATES = 40;

const WeatherSchema = z.object({
  temperatureC: z.number().min(-60).max(60),
  feelsLikeC: z.number().min(-70).max(70),
  precipitationChance: z.number().min(0).max(1),
  windKph: z.number().min(0).max(300),
});

const RankGarmentSchema = z.object({
  id: z.string().min(1).max(64),
  category: z.enum(CATEGORIES),
  subcategory: z.string().max(60),
  primaryColor: z.string().max(40),
  secondaryColor: z.string().max(40).nullish(),
  pattern: z.enum(PATTERNS),
  material: z.string().max(60),
  formality: z.number().int().min(1).max(5),
});

export const RankOutfitsRequestSchema = z
  .object({
    context: z.object({
      occasion: z.enum(OCCASIONS).nullish(),
      style: z.enum(STYLES).nullish(),
      season: z.enum(SEASONS).nullish(),
      weather: WeatherSchema.nullish(),
      preferences: z.object({
        preferredStyles: z.array(z.enum(STYLES)).max(4),
        favoriteColors: z.array(z.string().max(40)).max(30),
        avoidedColors: z.array(z.string().max(40)).max(30),
      }),
    }),
    garments: z.array(RankGarmentSchema).min(1).max(200),
    candidates: z
      .array(z.object({ id: z.string().min(1).max(16), garmentIds: z.array(z.string()).min(2).max(5) }))
      .min(1)
      .max(MAX_CANDIDATES),
    count: z.number().int().min(1).max(5),
  })
  .superRefine((value, ctx) => {
    const ids = new Set(value.garments.map((g) => g.id));
    const candidateIds = new Set<string>();
    value.candidates.forEach((candidate, index) => {
      if (candidateIds.has(candidate.id)) {
        ctx.addIssue({ code: "custom", message: `Duplicate candidate id ${candidate.id}`, path: ["candidates", index, "id"] });
      }
      candidateIds.add(candidate.id);
      for (const garmentId of candidate.garmentIds) {
        if (!ids.has(garmentId)) {
          ctx.addIssue({ code: "custom", message: `Unknown garment id ${garmentId}`, path: ["candidates", index] });
        }
      }
    });
  });

export type RankOutfitsRequest = z.infer<typeof RankOutfitsRequestSchema>;

export const AIRankOutputSchema = z.object({
  outfits: z.array(
    z.object({
      candidateId: z.string().describe("One of the candidate ids from the input, e.g. 'c3'"),
      title: z.string().describe("2 to 6 words, e.g. 'Navy and beige classic'"),
      reasoning: z.string().describe("Exactly one sentence explaining why it works today"),
    }),
  ),
});

export const RankedOutfitSchema = z.object({
  candidateId: z.string(),
  garmentIds: z.array(z.string()).min(2),
  title: z.string().min(1).max(60),
  reasoning: z.string().min(1).max(220),
});

export const RankOutfitsResponseSchema = z.object({
  outfits: z.array(RankedOutfitSchema).min(1).max(5),
});

export type RankOutfitsResponse = z.infer<typeof RankOutfitsResponseSchema>;

/**
 * Keeps only candidates that were in the request (so every garment id belongs to the user),
 * removes duplicates, trims wording and caps the count. Returns null if nothing valid remains.
 */
export function normalizeRanking(output: z.infer<typeof AIRankOutputSchema>, request: RankOutfitsRequest): RankOutfitsResponse | null {
  const candidates = new Map(request.candidates.map((c) => [c.id, c.garmentIds]));
  const seen = new Set<string>();
  const outfits: RankOutfitsResponse["outfits"] = [];
  for (const item of output.outfits) {
    const garmentIds = candidates.get(item.candidateId.trim());
    if (!garmentIds || seen.has(item.candidateId)) continue;
    const title = cleanText(item.title, 60);
    const reasoning = cleanText(item.reasoning, 220);
    if (!title || !reasoning) continue;
    seen.add(item.candidateId);
    outfits.push({ candidateId: item.candidateId.trim(), garmentIds, title, reasoning });
    if (outfits.length >= request.count) break;
  }
  const result = RankOutfitsResponseSchema.safeParse({ outfits });
  return result.success ? result.data : null;
}
