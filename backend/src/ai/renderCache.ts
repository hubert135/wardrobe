import type { ImagePayload } from "../schemas/common.js";

/** Finished renders by request, so the same garment or outfit is never paid for twice. */
export interface RenderCache {
  get(key: string): Promise<ImagePayload | null>;
  put(key: string, image: ImagePayload): Promise<void>;
}

/** In-memory cache (tests, serverless); the Node server uses files instead. */
export class MemoryRenderCache implements RenderCache {
  private readonly entries = new Map<string, ImagePayload>();
  constructor(private readonly limit = 200) {}

  async get(key: string) {
    return this.entries.get(key) ?? null;
  }

  async put(key: string, image: ImagePayload) {
    if (this.entries.size >= this.limit) {
      const oldest = this.entries.keys().next().value;
      if (oldest !== undefined) this.entries.delete(oldest);
    }
    this.entries.set(key, image);
  }
}

/** JSON with sorted keys, so equal requests always give the same key. */
function stableJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stableJSON(v)}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

/** SHA-256 hex of the request (Web Crypto: works in Node, Workers and Vercel). */
export async function renderKey(kind: string, input: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(`${kind}\n${stableJSON(input)}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
