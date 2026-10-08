import { z } from "zod";

/** ~4 MB of image bytes once decoded. The app sends ~1600 px JPEGs well below this. */
export const MAX_IMAGE_BASE64_LENGTH = 5_600_000;

export const ImagePayloadSchema = z.object({
  mediaType: z.enum(["image/jpeg", "image/png", "image/webp", "image/gif"]),
  data: z
    .string()
    .min(100, "Image data is too small")
    .max(MAX_IMAGE_BASE64_LENGTH, "Image is too large")
    .regex(/^[A-Za-z0-9+/=\r\n]+$/, "Image data must be base64"),
});

export type ImagePayload = z.infer<typeof ImagePayloadSchema>;

export const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max);

/** Trims, collapses whitespace and caps length; returns null for empty strings. */
export function cleanText(value: string | null | undefined, maxLength: number): string | null {
  if (value == null) return null;
  const cleaned = value.replace(/\s+/g, " ").trim();
  if (!cleaned) return null;
  return cleaned.length > maxLength ? `${cleaned.slice(0, maxLength - 1).trimEnd()}…` : cleaned;
}
