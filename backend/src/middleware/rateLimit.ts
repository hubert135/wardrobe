import type { MiddlewareHandler } from "hono";
import { ApiError } from "../errors.js";

/**
 * Fixed-window, in-memory rate limiter. Good enough for one instance; on serverless platforms each
 * instance has its own window, so use a shared store (Cloudflare KV / Durable Objects, Upstash Redis)
 * behind the same interface in production.
 */
export class RateLimiter {
  private readonly windows = new Map<string, { start: number; count: number }>();

  constructor(
    readonly limit: number,
    readonly windowMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  check(key: string): { allowed: boolean; retryAfterSeconds: number; remaining: number } {
    const now = this.now();
    let window = this.windows.get(key);
    if (!window || now - window.start >= this.windowMs) {
      window = { start: now, count: 0 };
      this.windows.set(key, window);
      if (this.windows.size > 10_000) this.evict(now);
    }
    window.count += 1;
    const allowed = window.count <= this.limit;
    return {
      allowed,
      remaining: Math.max(this.limit - window.count, 0),
      retryAfterSeconds: allowed ? 0 : Math.ceil((window.start + this.windowMs - now) / 1000),
    };
  }

  private evict(now: number) {
    for (const [key, window] of this.windows) {
      if (now - window.start >= this.windowMs) this.windows.delete(key);
    }
  }
}

export function rateLimit(limiter: RateLimiter, keyOf: (c: Parameters<MiddlewareHandler>[0]) => string): MiddlewareHandler {
  return async (c, next) => {
    const result = limiter.check(keyOf(c));
    c.header("X-RateLimit-Remaining", String(result.remaining));
    if (!result.allowed) {
      c.header("Retry-After", String(result.retryAfterSeconds));
      throw new ApiError(429, "rate_limited", "Too many requests. Please try again later.");
    }
    await next();
  };
}
