import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { ReferenceImageStore } from "./ai/outfitPhoto.js";
import type { RenderCache } from "./ai/renderCache.js";
import type { ImagePayload } from "./schemas/common.js";

const SAFE_NAME = /^[a-z0-9-]{1,80}\.jpg$/;

/** Renders as JPEG files named by request hash (Node server only). */
export class FileRenderCache implements RenderCache {
  constructor(private readonly directory: string) {}

  async get(key: string): Promise<ImagePayload | null> {
    if (!/^[a-f0-9]{64}$/.test(key)) return null;
    try {
      const bytes = await readFile(join(this.directory, `${key}.jpg`));
      return { mediaType: "image/jpeg", data: bytes.toString("base64") };
    } catch {
      return null;
    }
  }

  async put(key: string, image: ImagePayload): Promise<void> {
    if (!/^[a-f0-9]{64}$/.test(key)) return;
    await mkdir(this.directory, { recursive: true });
    await writeFile(join(this.directory, `${key}.jpg`), Buffer.from(image.data, "base64"));
  }
}

/** Reference images such as the house model, as files. */
export class FileReferenceStore implements ReferenceImageStore {
  constructor(private readonly directory: string) {}

  async get(name: string): Promise<Uint8Array | null> {
    if (!SAFE_NAME.test(name)) return null;
    return readFile(join(this.directory, name)).catch(() => null);
  }

  async put(name: string, bytes: Uint8Array): Promise<void> {
    if (!SAFE_NAME.test(name)) return;
    await mkdir(this.directory, { recursive: true });
    await writeFile(join(this.directory, name), bytes);
  }
}
