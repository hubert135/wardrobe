import { z } from "zod";
import { clamp, cleanText, ImagePayloadSchema } from "./common.js";
import { CATEGORIES } from "./taxonomy.js";

export const MAX_ORDER_TEXT_LENGTH = 30_000;

export const ParseOrderRequestSchema = z
  .object({
    text: z.string().max(MAX_ORDER_TEXT_LENGTH).nullish(),
    image: ImagePayloadSchema.nullish(),
  })
  .refine((value) => (value.text?.trim().length ?? 0) >= 20 || value.image != null, {
    message: "Provide the order text (at least 20 characters) or a screenshot",
  });

export const AIOrderItemSchema = z.object({
  name: z.string(),
  brand: z.string().nullable(),
  category: z.enum(CATEGORIES),
  color: z.string().nullable(),
  size: z.string().nullable(),
  price: z.number().nullable().describe("Price paid per item, as a number without currency symbol"),
  currency: z.string().nullable().describe("ISO 4217 code, e.g. EUR, PLN"),
  purchaseDate: z.string().nullable().describe("Order date as YYYY-MM-DD"),
  imageUrl: z.string().nullable().describe("Product image URL only if it literally appears in the input"),
});

export const AIOrderOutputSchema = z.object({
  isClothingOrder: z.boolean(),
  items: z.array(AIOrderItemSchema),
});

export const ParsedOrderItemSchema = z.object({
  name: z.string().min(1).max(120),
  brand: z.string().max(60).nullable(),
  category: z.enum(CATEGORIES),
  color: z.string().max(40).nullable(),
  size: z.string().max(30).nullable(),
  price: z.number().min(0).nullable(),
  currency: z.string().regex(/^[A-Z]{3}$/).nullable(),
  purchaseDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  imageUrl: z.url({ protocol: /^https?$/ }).nullable(),
});

export const ParseOrderResponseSchema = z.object({
  items: z.array(ParsedOrderItemSchema).max(50),
});

export type ParseOrderResponse = z.infer<typeof ParseOrderResponseSchema>;

function safeImageUrl(value: string | null, sourceText: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    // Never pass on a URL the model could have invented: it must appear in the input text.
    if (sourceText !== null && !sourceText.includes(value)) return null;
    return url.toString();
  } catch {
    return null;
  }
}

function safeDate(value: string | null): string | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(date.getTime()) ? null : value;
}

/**
 * Cleans AI output. `sourceText` is the order text (null for screenshots, where URLs cannot appear).
 * Returns an empty item list for non-clothing orders.
 */
export function normalizeOrder(output: z.infer<typeof AIOrderOutputSchema>, sourceText: string | null): ParseOrderResponse | null {
  if (!output.isClothingOrder) return { items: [] };
  const items = output.items.slice(0, 50).map((item) => {
    const currency = item.currency?.trim().toUpperCase() ?? null;
    return {
      name: cleanText(item.name, 120) ?? "Item",
      brand: cleanText(item.brand, 60),
      category: item.category,
      color: cleanText(item.color, 40),
      size: cleanText(item.size, 30),
      price: item.price != null && Number.isFinite(item.price) && item.price >= 0 ? Math.round(clamp(item.price, 0, 1_000_000) * 100) / 100 : null,
      currency: currency && /^[A-Z]{3}$/.test(currency) ? currency : null,
      purchaseDate: safeDate(item.purchaseDate),
      imageUrl: sourceText === null ? null : safeImageUrl(item.imageUrl, sourceText),
    };
  });
  const result = ParseOrderResponseSchema.safeParse({ items });
  return result.success ? result.data : null;
}
