import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { z } from "zod";
import type { ImagePayload } from "../schemas/common.js";

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export type InputBlock = { type: "text"; text: string } | { type: "image"; image: ImagePayload };

export interface StructuredRequest<T> {
  /** Name for logs/metrics only. */
  task: string;
  system: string;
  content: InputBlock[];
  schema: z.ZodType<T>;
  maxTokens?: number;
}

/** The model returned something that does not match the schema (or refused). Safe to retry. */
export class AIOutputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AIOutputError";
  }
}

/** The AI provider could not be reached or rejected the request. */
export class AIUnavailableError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "AIUnavailableError";
  }
}

export interface AIClient {
  generate<T>(request: StructuredRequest<T>): Promise<T>;
}

export interface AnthropicClientOptions {
  apiKey: string;
  model: string;
  effort: Effort;
  timeoutMs?: number;
}

/** Structured-output calls to Claude. The schema is enforced by the API and re-validated by the SDK. */
export class AnthropicAIClient implements AIClient {
  private readonly client: Anthropic;

  constructor(private readonly options: AnthropicClientOptions) {
    this.client = new Anthropic({ apiKey: options.apiKey, timeout: options.timeoutMs ?? 60_000, maxRetries: 2 });
  }

  async generate<T>(request: StructuredRequest<T>): Promise<T> {
    let response;
    try {
      response = await this.client.beta.messages.parse({
        model: this.options.model,
        max_tokens: request.maxTokens ?? 8_000,
        // Server-side fallback: if a safety classifier declines, the API retries on a fallback model in the same call.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { effort: this.options.effort, format: betaZodOutputFormat(request.schema) },
        system: request.system,
        messages: [{ role: "user", content: request.content.map(toContentBlock) }],
      });
    } catch (error) {
      if (error instanceof Anthropic.RateLimitError) throw new AIUnavailableError("AI rate limit reached", true);
      if (error instanceof Anthropic.BadRequestError) throw new AIUnavailableError(`AI rejected the request: ${error.message}`, false);
      if (error instanceof Anthropic.AuthenticationError) throw new AIUnavailableError("AI credentials are invalid", false);
      if (error instanceof Anthropic.APIConnectionError) throw new AIUnavailableError("AI provider unreachable", true);
      if (error instanceof Anthropic.APIError) throw new AIUnavailableError(`AI provider error (${error.status ?? "unknown"})`, true);
      // Parsing failures from the SDK helper surface as plain errors: treat as invalid output.
      throw new AIOutputError(error instanceof Error ? error.message : "Invalid AI output");
    }

    if (response.stop_reason === "refusal") throw new AIOutputError("The model declined this request");
    if (response.stop_reason === "max_tokens") throw new AIOutputError("The model output was truncated");
    if (response.parsed_output == null) throw new AIOutputError("The model output did not match the schema");
    return response.parsed_output as T;
  }
}

function toContentBlock(block: InputBlock): Anthropic.Beta.Messages.BetaContentBlockParam {
  if (block.type === "text") return { type: "text", text: block.text };
  return {
    type: "image",
    source: { type: "base64", media_type: block.image.mediaType, data: block.image.data.replace(/\s/g, "") },
  };
}

/**
 * Runs a structured request, validates it with `normalize`, and retries exactly once when the output is
 * invalid (schema mismatch, refusal, truncation, or normalization rejected it).
 */
export async function generateWithRetry<Raw, Result>(
  ai: AIClient,
  request: StructuredRequest<Raw>,
  normalize: (raw: Raw) => Result | null,
): Promise<Result> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const raw = await ai.generate(request);
      const result = normalize(raw);
      if (result !== null) return result;
      lastError = new AIOutputError("The model output failed validation");
    } catch (error) {
      if (!(error instanceof AIOutputError)) throw error;
      lastError = error;
    }
  }
  throw lastError instanceof AIOutputError ? lastError : new AIOutputError("Invalid AI output");
}
