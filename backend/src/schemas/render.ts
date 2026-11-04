import { z } from "zod";
import { ImagePayloadSchema } from "./common.js";
import { CATEGORIES, PATTERNS } from "./taxonomy.js";

/** Optional attributes from recognition; they help the image model pick the right item and keep its color. */
export const RenderGarmentHintsSchema = z.object({
  name: z.string().max(80).nullish(),
  category: z.enum(CATEGORIES),
  subcategory: z.string().max(60).nullish(),
  primaryColor: z.string().max(40),
  secondaryColor: z.string().max(40).nullish(),
  pattern: z.enum(PATTERNS).nullish(),
  material: z.string().max(60).nullish(),
});

export type RenderGarmentHints = z.infer<typeof RenderGarmentHintsSchema>;

/** Either the user's photo (optionally with hints) or, for garments without a photo, a description alone. */
export const RenderProductPhotoRequestSchema = z
  .object({
    image: ImagePayloadSchema.nullish(),
    garment: RenderGarmentHintsSchema.nullish(),
  })
  .refine((value) => value.image != null || value.garment != null, {
    message: "Send a photo or a garment description",
  });

export const RenderProductPhotoResponseSchema = z.object({
  image: ImagePayloadSchema,
});
