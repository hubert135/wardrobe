import OpenAI, { toFile } from "openai";
import type { ImageQuality } from "../config.js";
import type { ImagePayload } from "../schemas/common.js";
import type { RenderGarmentHints } from "../schemas/render.js";
import { AIUnavailableError } from "./client.js";

/** Turns a phone photo of a garment into an online-store style product photo. */
export interface ProductPhotoRenderer {
  render(input: { image: ImagePayload; garment: RenderGarmentHints | null }): Promise<ImagePayload>;
}

/** Thrown when no image provider is configured (no OPENAI_API_KEY). */
export class RendererNotConfiguredError extends Error {}

/**
 * The instruction for the image model. Fidelity first: the garment must stay the same garment;
 * only the presentation changes.
 */
export function buildProductPhotoPrompt(garment: RenderGarmentHints | null): string {
  const described = garment
    ? [
        garment.primaryColor,
        garment.secondaryColor ? `with ${garment.secondaryColor}` : null,
        garment.pattern && garment.pattern !== "solid" ? garment.pattern : null,
        garment.material,
        garment.subcategory || garment.category,
      ]
        .filter(Boolean)
        .join(" ")
    : null;

  return [
    "Create a professional e-commerce product photo of the clothing item in the input photo, like the product images in a premium online fashion store.",
    described
      ? `The item is a ${described}${garment?.name ? ` ("${garment.name}")` : ""}. If the photo shows several items, show only this one. If this description conflicts with the photo, follow the photo.`
      : null,
    "Keep the garment exactly as it is: the same colors and shades, pattern, knit or fabric texture, stitching, buttons, zips, pockets, collar and cuffs, and any logo, label or print in the same place and size. Do not add, remove or redesign details, and do not change the color.",
    "Presentation: front view, centered, upright and symmetrical, neatly shaped as if worn by an invisible mannequin (ghost mannequin), sleeves relaxed along the body, smooth and wrinkle-free, natural proportions. Trousers and shorts are shown front-facing at full length; shoes are shown as a pair in a three-quarter side view; small accessories are laid out neatly.",
    "Pure white seamless background, soft even studio lighting, a very subtle soft shadow below the item, the item filling most of the frame with a small even margin.",
    "No person, no hanger, no mannequin visible, no props, no text, no watermark, no border.",
  ]
    .filter(Boolean)
    .join("\n");
}

export interface OpenAIRendererOptions {
  apiKey: string;
  model: string;
  quality: ImageQuality;
  timeoutMs?: number;
}

export class OpenAIProductPhotoRenderer implements ProductPhotoRenderer {
  private readonly client: OpenAI;

  constructor(private readonly options: OpenAIRendererOptions) {
    // Image edits can take up to a minute or two; keep the SDK's own retries low to stay under client timeouts.
    this.client = new OpenAI({ apiKey: options.apiKey, timeout: options.timeoutMs ?? 150_000, maxRetries: 1 });
  }

  async render(input: { image: ImagePayload; garment: RenderGarmentHints | null }): Promise<ImagePayload> {
    const extension = input.image.mediaType.split("/")[1] ?? "jpeg";
    const file = await toFile(Buffer.from(input.image.data, "base64"), `garment.${extension}`, { type: input.image.mediaType });
    try {
      const response = await this.client.images.edit({
        model: this.options.model,
        image: file,
        prompt: buildProductPhotoPrompt(input.garment),
        size: "1024x1536",
        quality: this.options.quality,
        background: "opaque",
        output_format: "jpeg",
        output_compression: 90,
        n: 1,
      });
      const data = response.data?.[0]?.b64_json;
      if (!data) throw new AIUnavailableError("The image model returned no image", true);
      return { mediaType: "image/jpeg", data };
    } catch (error) {
      if (error instanceof AIUnavailableError) throw error;
      if (error instanceof OpenAI.RateLimitError) throw new AIUnavailableError("Image provider rate limit reached", true);
      if (error instanceof OpenAI.AuthenticationError) throw new AIUnavailableError("Image provider credentials are invalid", false);
      if (error instanceof OpenAI.BadRequestError) throw new AIUnavailableError(`Image provider rejected the request: ${error.message}`, false);
      if (error instanceof OpenAI.APIError) throw new AIUnavailableError(`Image provider error (${error.status ?? "unknown"})`, true);
      throw new AIUnavailableError("Image provider unreachable", true);
    }
  }
}
