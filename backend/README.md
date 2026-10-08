# Wardrobe backend

A stateless TypeScript service whose only job is to proxy AI calls for the Wardrobe app, so the Anthropic API key never ships in the app. Built with [Hono](https://hono.dev), `@anthropic-ai/sdk` and Zod. It runs on Node, Cloudflare Workers and Vercel.

## Endpoints

All AI endpoints need `Authorization: Bearer <sessionToken>` and are rate limited per user. Errors always look like `{ "error": { "code": "...", "message": "..." } }`.

| Method & path | Body | Response |
|---|---|---|
| `GET /health` | | `{ status: "ok" }` |
| `POST /v1/auth/session` | `{ identityToken }` (Sign in with Apple JWT) | `{ sessionToken, userId, expiresAt }` |
| `POST /v1/garments/analyze` | `{ image: { mediaType, data(base64) } }` | `{ garments: [{ name, category, subcategory, primaryColor, secondaryColor, pattern, material, formality, seasons, brand, confidence }] }`, or `422 no_garment_found` |
| `POST /v1/orders/parse` | `{ text }` or `{ image }` | `{ items: [{ name, brand, category, color, size, price, currency, purchaseDate, imageUrl }] }` |
| `POST /v1/outfits/rank` | `{ context, garments, candidates, count }` | `{ outfits: [{ candidateId, garmentIds, title, reasoning }] }` |

How every AI call works:

1. The request is validated with Zod (`src/schemas/*`).
2. Claude is called with structured outputs (`output_config.format`) generated from a Zod schema.
3. The output is normalized: values clamped, text trimmed, unknown candidate ids dropped, and image URLs that don't appear in the input dropped.
4. If the output is invalid (schema mismatch, refusal, truncation, or nothing valid left after normalizing), the call is **retried once**. A second failure returns `502 ai_invalid_output`. If the provider is down, the response is `503 ai_unavailable`.

The model name lives in one config value, `AI_MODEL` (default `claude-opus-5-5`). Effort is `AI_EFFORT` (default `low`). Requests opt into Anthropic's server-side refusal fallback (`fallbacks: "default"`). Prompts are in `src/ai/prompts.ts`.

## Run locally

```bash
cp .env.example .env     # set ANTHROPIC_API_KEY and SESSION_SECRET (openssl rand -hex 32)
npm install
npm run dev              # http://localhost:8787, reloads on change
```

For the Simulator, set `AUTH_DEV_BYPASS=true`. The app's **Development sign-in** button (Debug builds) then sends the identity token `"dev"`. Never enable this in production.

```bash
curl -s localhost:8787/v1/auth/session -H 'content-type: application/json' -d '{"identityToken":"dev"}'
```

## Tests

```bash
npm test          # vitest: schema validation, normalization, auth, retry, rate limiting
npm run typecheck
```

The tests use a scripted fake AI client, so they need no network and no API key.

## Deploy

### Cloudflare Workers

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put SESSION_SECRET
npx wrangler deploy        # uses wrangler.toml (entry: src/worker.ts)
```

### Vercel

Import the `backend` folder as a project. `api/index.ts` runs the app on the Edge runtime, and `vercel.json` routes every path to it. Set the environment variables from `.env.example` in the project settings.

### Any Node host (Render, Fly.io, Railway, a VM)

```bash
npm ci && npm run build && npm start   # PORT defaults to 8787
```

After deploying, set `API_BASE_URL` in the app's `project.yml` to the public HTTPS URL.

## Production notes

- **Rate limiting** is in memory, so each serverless instance or isolate keeps its own counters. For real traffic, back `RateLimiter` with a shared store (Cloudflare Durable Objects or KV, Upstash Redis) through the same `check(key)` interface.
- **Apple keys** are fetched from `https://appleid.apple.com/auth/keys` and cached by `jose`.
- **Logs** record only the event name, path and error message. Request bodies (images, order text) and tokens are never logged.
- **Body size** is capped at 6 MB per request, and images at about 4 MB decoded.
