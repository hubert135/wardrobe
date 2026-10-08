import { z } from "zod";
import { clamp, cleanText, ImagePayloadSchema } from "./common.js";
import { CATEGORIES, COLORS, PATTERNS, SEASONS } from "./taxonomy.js";

// ---- Request ----

export const AnalyzeGarmentRequestSchema = z.object({
  image: ImagePayloadSchema,
});

// ---- AI output (kept simple: structured outputs support a subset of JSON Schema) ----

export const AIGarmentSchema = z.object({
  name: z.string().describe("Short descriptive name, e.g. 'Navy oxford shirt'"),
  category: z.enum(CATEGORIES),
  subcategory: z.string().describe("Specific type, e.g. 'oxford shirt', 'chelsea boots'. Empty string if unclear."),
  primaryColor: z.enum(COLORS),
  secondaryColor: z.enum(COLORS).nullable(),
  pattern: z.enum(PATTERNS),
  material: z.string().nullable().describe("Only if visible with reasonable certainty"),
  formality: z.number().describe("Integer 1 to 5: 1 sporty, 3 smart casual, 5 formal"),
  seasons: z.array(z.enum(SEASONS)),
  brand: z.string().nullable().describe("Only if a logo or label is clearly visible"),
  confidence: z.number().describe("0 to 1: how sure you are about category and color"),
});

export const AIAnalyzeOutputSchema = z.object({
  garments: z.array(AIGarmentSchema),
});

// ---- Response (what the app receives) ----

export const AnalyzedGarmentSchema = z.object({
  name: z.string().min(1).max(80),
  category: z.enum(CATEGORIES),
  subcategory: z.string().max(60),
  primaryColor: z.enum(COLORS),
  secondaryColor: z.enum(COLORS).nullable(),
  pattern: z.enum(PATTERNS),
  material: z.string().max(60).nullable(),
  formality: z.number().int().min(1).max(5),
  seasons: z.array(z.enum(SEASONS)),
  brand: z.string().max(60).nullable(),
  confidence: z.number().min(0).max(1),
});

export const AnalyzeGarmentResponseSchema = z.object({
  garments: z.array(AnalyzedGarmentSchema).max(10),
});

export type AnalyzeGarmentResponse = z.infer<typeof AnalyzeGarmentResponseSchema>;

/** Clamps and cleans AI output into the response contract. Returns null if the output is unusable. */
export function normalizeAnalysis(output: z.infer<typeof AIAnalyzeOutputSchema>): AnalyzeGarmentResponse | null {
  const garments = output.garments
    .filter((g) => g.category !== "other" || g.confidence >= 0.3)
    .slice(0, 10)
    .map((g) => ({
      name: cleanText(g.name, 80) ?? `${g.primaryColor} ${g.category}`,
      category: g.category,
      subcategory: cleanText(g.subcategory, 60) ?? "",
      primaryColor: g.primaryColor,
      secondaryColor: g.secondaryColor === g.primaryColor ? null : g.secondaryColor,
      pattern: g.pattern,
      material: cleanText(g.material, 60),
      formality: clamp(Math.round(g.formality), 1, 5),
      seasons: [...new Set(g.seasons)],
      brand: cleanText(g.brand, 60),
      confidence: clamp(Number.isFinite(g.confidence) ? g.confidence : 0, 0, 1),
    }));
  const result = AnalyzeGarmentResponseSchema.safeParse({ garments });
  return result.success ? result.data : null;
}
