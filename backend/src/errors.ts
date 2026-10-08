import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { z } from "zod";

export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
  }
}

export function errorResponse(c: Context, error: ApiError) {
  return c.json({ error: { code: error.code, message: error.message, ...(error.details ? { details: error.details } : {}) } }, error.status);
}

/** Parses the JSON body with a Zod schema or throws a 400 with readable issues. */
export async function parseBody<T>(c: Context, schema: z.ZodType<T>): Promise<T> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw new ApiError(400, "invalid_json", "The request body must be valid JSON.");
  }
  const result = schema.safeParse(body);
  if (!result.success) {
    const issues = result.error.issues.slice(0, 10).map((issue) => ({ path: issue.path.join("."), message: issue.message }));
    throw new ApiError(400, "invalid_request", issues[0]?.message ?? "Invalid request.", issues);
  }
  return result.data;
}
