import { toFile } from "openai";
import type { ImagePayload } from "../schemas/common.js";
import type { OutfitSlot, RenderGarmentHints } from "../schemas/render.js";
import {
  describe,
  firstImage,
  imageParams,
  mapImageError,
  openAIClient,
  type OpenAIRendererOptions,
} from "./productPhoto.js";

export interface OutfitRenderItem {
  slot: OutfitSlot;
  garment: RenderGarmentHints;
  /** Product photo of the garment, when the app has one: the model copies its exact look. */
  image: ImagePayload | null;
}

/**
 * Shows a whole outfit worn by a model. "house" is the app's consistent stand-in model; a user's own avatar
 * can later be another reference image passed the same way.
 */
export interface OutfitPhotoRenderer {
  render(input: { items: OutfitRenderItem[]; model: "house" }): Promise<ImagePayload>;
}

/** Keeps generated reference images (the house model) between restarts. */
export interface ReferenceImageStore {
  get(name: string): Promise<Uint8Array | null>;
  put(name: string, bytes: Uint8Array): Promise<void>;
}

/** Bump to create a new house model; cached outfit renders are keyed by it too. */
export const HOUSE_MODEL_VERSION = "house-model-v1";

export const HOUSE_MODEL_PROMPT = [
  "A photorealistic full-length studio photograph of a male fashion model in his early thirties: average athletic build, about 183 cm tall, short neat dark brown hair, light stubble, calm friendly expression.",
  "He stands in a relaxed natural pose facing the camera, arms relaxed at his sides.",
  "He wears a plain fitted white crew-neck T-shirt, plain light grey straight-leg trousers and plain white leather sneakers, all without logos.",
  "Plain light warm-grey seamless studio backdrop, soft natural daylight, a gentle shadow on the floor. The whole figure from head to shoes is visible with a small margin.",
  "Editorial lookbook quality, sharp focus, true-to-life colors. No text, no watermark, no props.",
].join("\n");

const SLOT_LABEL: Record<OutfitSlot, string> = {
  outerwear: "Outer layer",
  top: "Top",
  bottom: "Bottoms",
  shoes: "Shoes",
  accessory: "Accessory",
};

const SLOT_ORDER: OutfitSlot[] = ["outerwear", "top", "bottom", "shoes", "accessory"];

/** Items in wearing order; item photos are numbered after the model photo (image 1). */
export function orderedItems(items: OutfitRenderItem[]): OutfitRenderItem[] {
  return [...items].sort((a, b) => SLOT_ORDER.indexOf(a.slot) - SLOT_ORDER.indexOf(b.slot));
}

export function buildOutfitPrompt(items: OutfitRenderItem[]): string {
  let imageNumber = 1;
  const lines = orderedItems(items).map((item) => {
    const reference = item.image ? ` (exactly as in image ${++imageNumber})` : "";
    const name = item.garment.name ? `, "${item.garment.name}"` : "";
    return `- ${SLOT_LABEL[item.slot]}: ${describe(item.garment)}${name}${reference}`;
  });
  const hasOuter = items.some((item) => item.slot === "outerwear");
  return [
    "Image 1 shows our house model. Create a new realistic full-length fashion photograph of exactly this man (same face, hair, skin tone, body shape and height) wearing the outfit below instead of his current clothes.",
    "Outfit:",
    ...lines,
    "Copy each item's color, fabric, texture and details from its photo; where there is no photo, follow the description. Do not add garments that are not listed, apart from plain socks.",
    "Every piece is plain and unbranded: no logos, brand names, labels, monograms or text anywhere.",
    "Fit and styling: modern, well-fitted menswear in natural proportions. Shirts and knitted polos are tucked into tailored trousers and chinos; T-shirts, sweaters and hoodies hang naturally. Trousers sit at the waist and rest lightly on the shoes.",
    hasOuter ? "The outer layer is worn over the top and left open, so the top is visible." : null,
    "Pose and framing: standing in a relaxed natural pose, body turned slightly, calm expression, arms relaxed; the whole figure from head to shoes is visible with a small margin above the head and below the shoes.",
    "Plain light warm-grey seamless studio backdrop, soft natural daylight, a gentle shadow on the floor. Photorealistic editorial lookbook quality, sharp focus, true-to-life colors.",
    "No text, no watermark, no other people, no props.",
  ]
    .filter(Boolean)
    .join("\n");
}

export class OpenAIOutfitRenderer implements OutfitPhotoRenderer {
  private readonly client;
  private houseModel: Promise<Uint8Array> | null = null;

  constructor(private readonly options: OpenAIRendererOptions & { store?: ReferenceImageStore }) {
    this.client = openAIClient(options);
  }

  async render(input: { items: OutfitRenderItem[]; model: "house" }): Promise<ImagePayload> {
    try {
      const model = await this.referenceModel();
      const images = [await toFile(model, "model.jpg", { type: "image/jpeg" })];
      for (const item of orderedItems(input.items)) {
        if (!item.image) continue;
        const extension = item.image.mediaType.split("/")[1] ?? "jpeg";
        images.push(await toFile(Buffer.from(item.image.data, "base64"), `${item.slot}.${extension}`, { type: item.image.mediaType }));
      }
      const response = await this.client.images.edit({ ...imageParams(this.options), image: images, prompt: buildOutfitPrompt(input.items) });
      return firstImage(response);
    } catch (error) {
      mapImageError(error);
    }
  }

  /** The house model photo: loaded from the store, or generated once and stored. */
  private referenceModel(): Promise<Uint8Array> {
    this.houseModel ??= this.loadOrCreateModel().catch((error: unknown) => {
      this.houseModel = null;
      throw error;
    });
    return this.houseModel;
  }

  private async loadOrCreateModel(): Promise<Uint8Array> {
    const name = `${HOUSE_MODEL_VERSION}.jpg`;
    const stored = await this.options.store?.get(name).catch(() => null);
    if (stored) return stored;
    const image = firstImage(await this.client.images.generate({ ...imageParams(this.options), prompt: HOUSE_MODEL_PROMPT }));
    const bytes = Buffer.from(image.data, "base64");
    await this.options.store?.put(name, bytes).catch(() => undefined);
    return bytes;
  }
}
