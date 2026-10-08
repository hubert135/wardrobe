# Wardrobe (working name)

A native iOS digital closet for one person (menswear, smart casual and business). It knows what you own, builds outfits for the day's weather and occasion, and ranks purchases by how many new outfits they unlock.

> **Status:** MVP source for all 8 stages. The backend is built and tested (`npm test`: 29 passing). The Swift code was written on a Windows machine without Xcode, so it has **not been compiled or run yet**. Run `make test` on a Mac first (see [First build on a Mac](#first-build-on-a-mac)).

## Repository layout

```
project.yml                 XcodeGen spec (app, share extension, unit + UI tests)
Makefile, scripts/          build / test / run on the Simulator
App/                        iOS app (SwiftUI, SwiftData)
  Models/                   SwiftData models (Garment, Outfit, OutfitSlot, WishlistItem, UserProfile)
  Storage/                  ImageStore protocol + file store, repository, Keychain, container factory
  Networking/               WardrobeAPI protocol, HTTP client, wire DTOs
  Services/                 auth, image processing + background removal, recognition, order import,
                            weather (WeatherKit + mock), outfit pipeline, shop, notifications, export, seed
  ViewModels/               @Observable view models
  Views/                    Today, Closet, Add, Outfits, Shop, Profile, Onboarding, Components
Packages/OutfitEngine/      pure Swift package: rules, candidates, scoring, gap analysis + XCTest suite
ShareExtension/             "Add to Wardrobe" share extension (order text / screenshot)
Shared/                     code shared by app and extension (App Group hand-off)
Tests/WardrobeTests/        unit tests (response parsing, weather mapping, shop links, inference)
UITests/WardrobeUITests/    UI test: add garment, generate outfit, "I'm wearing this"
backend/                    TypeScript AI proxy (Hono + Anthropic SDK + Zod)
```

### Architecture

- **MVVM.** `@Observable` view models talk to services behind protocols: `WardrobeRepository`, `ImageStore`, `WardrobeAPI`, `WeatherProvider`, `BackgroundRemoving`, `GarmentRecognizing`, `PurchaseImporter`, `ProductProvider`. Everything is wired once in `AppServices` (the composition root) and passed down through the SwiftUI environment.
- **OutfitEngine** has no UI, network or persistence dependencies. It is the single source of truth for outfit rules and gap counts, so it can be ported or mirrored for Android.
- **The backend only proxies AI calls.** The Anthropic key never ships in the app. Prompts and AI schemas live in `backend/src/ai/prompts.ts` and `backend/src/schemas/`, so Android can reuse them.

## Requirements

- macOS with Xcode 16 or newer (iOS 17 SDK minimum), `brew install xcodegen`
- Node.js 20+ for the backend
- An Anthropic API key for AI features

## Quick start

```bash
# 1. Backend
cd backend && cp .env.example .env    # set ANTHROPIC_API_KEY, SESSION_SECRET, AUTH_DEV_BYPASS=true
npm install && npm run dev            # http://localhost:8787
```

```bash
# 2. App (in another terminal, from the repo root)
make run-seed      # build, install and launch with 25 sample garments (Debug only)
# or
make run           # empty closet, onboarding
```

In the Simulator, go to **Profile → Development sign-in**. That gets a backend session through `AUTH_DEV_BYPASS`, without Apple. Real Sign in with Apple needs a development team (see below).

| Command | What it does |
|---|---|
| `make generate` | Generate `Wardrobe.xcodeproj` from `project.yml` |
| `make build` | Build for the first available iPhone simulator (`SIMULATOR_ID=<udid>` to override) |
| `make test` | `swift test` for OutfitEngine, then unit + UI tests via `xcodebuild test` |
| `make test-engine` | Engine tests only (fast, no Simulator) |
| `make run` / `make run-seed` | Build, install and launch in the Simulator |
| `make backend-dev` / `make backend-test` | Run / test the backend |

Pass `DEVELOPMENT_TEAM=ABCDE12345` to any `make` target to sign with your team.

### Test on your iPhone without a Mac (free)

GitHub's macOS machines compile the app, and [Sideloadly](https://sideloadly.io) installs it from Windows over a USB cable using your normal Apple ID. Nothing goes to the App Store.

1. Push this repo to GitHub. The **iOS** workflow (`.github/workflows/ios.yml`) runs on every push. Public repos get unlimited free macOS minutes; private repos get a limited free monthly allowance.
2. Open the repo's **Actions** tab, then the latest **iOS** run, then **Artifacts**, and download **Wardrobe-ipa**. Unzip it to get `Wardrobe.ipa`.
3. Install iTunes from apple.com (Sideloadly needs its iPhone drivers, and the Microsoft Store version doesn't work) and Sideloadly. Connect the iPhone, tap **Trust** on the phone, drag `Wardrobe.ipa` into Sideloadly, enter your Apple ID and press **Start**.
4. On the iPhone, open **Settings → General → VPN & Device Management**, trust your Apple ID, then turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts).
5. Open Wardrobe, go to onboarding step 2 and tap **Load sample closet** to get 25 garments. Then try Today, Closet, Builder and Shop.

What works without a server: the sample closet, manual adding, outfit suggestions (local engine), swap, "I'm wearing this", history, favorites, builder, shop ranking and links, statistics, export. Weather uses sample data. With a free Apple ID the app expires after 7 days; reinstall it with Sideloadly. If installing fails because of the share extension, use Sideloadly's advanced option to remove extensions (plug-ins).

**AI features (optional, needs an Anthropic API key, billed per use):** run the backend on your PC with `AUTH_DEV_BYPASS=true` (see [`backend/README.md`](backend/README.md)) and allow Node.js through the Windows firewall on private networks when asked. Then, on the iPhone (same Wi-Fi), enter your PC's address in **Profile → Server**, e.g. `192.168.1.20:8787` (find it with `ipconfig` under *IPv4 Address*), allow Local Network access, and tap **Development sign-in**.

### First build on a Mac

The Swift code has not been compiled yet. Expect a short fix-up pass:

1. `make test-engine`. This compiles and tests the pure engine package with no Xcode project involved.
2. `make build`. Send the compiler errors back to Claude Code if you want help fixing them.
3. `make test`, then `make run-seed`.

## Configuration

Build settings in `project.yml` (also overridable on the `xcodebuild` command line):

| Setting | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | `http://localhost:8787` | Backend URL written into Info.plist (`WardrobeAPIBaseURL`) |
| `WEATHER_PROVIDER` | `mock` | `mock` or `weatherkit` |
| `APP_GROUP_ID` | `group.com.example.wardrobe` | Shared container for the Share Extension |
| bundle ids | `com.example.wardrobe(.share)` | Change before using a real team |

Launch arguments: `-seed` loads the sample closet when it is empty (Debug). `-uiTesting` uses an in-memory store, mock weather, no network and a 7-garment seed.

### Enabling WeatherKit

WeatherKit needs a paid Apple Developer Program membership.

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), open your App ID (`com.example.wardrobe` or your own). Enable **WeatherKit** under both *Capabilities* and *App Services*. It can take about 30 minutes to become active.
2. In `project.yml`, uncomment `com.apple.developer.weatherkit: true` under the Wardrobe target's `entitlements`. Set `WEATHER_PROVIDER: weatherkit` and `DEVELOPMENT_TEAM`.
3. Run `make generate` and build to a device (or a Simulator signed with your team).
4. The weather card shows the Apple Weather attribution link, as Apple's terms require.

Until then, `MockWeatherProvider` returns 14 °C (feels like 12), 20 % rain. The last forecast is cached in `UserDefaults`, and the weather card shows it with an "Offline" label when a refresh fails.

### Sign in with Apple

Enable *Sign in with Apple* for the App ID and set `DEVELOPMENT_TEAM`. The app sends the identity token to `POST /v1/auth/session`. The backend verifies it against Apple's public keys (audience = `APPLE_BUNDLE_IDS`) and returns its own 30-day session token, which the app keeps in the Keychain.

### Share Extension

Mail → Share → **Add to Wardrobe** stores the order text (or a shared screenshot) in the App Group container. The next time Wardrobe becomes active, it opens the Add sheet on the **Order** tab and parses it. App Groups need the same team on both targets. Unsigned Simulator builds fall back to the app's own container, so the extension can't hand data over there.

## Backend

See [`backend/README.md`](backend/README.md) for endpoints, local run, tests and deployment (Cloudflare Workers, Vercel, any Node host).

## Privacy

- Photos and all closet data stay on the device (Application Support, SwiftData). Nothing is synced.
- Sent to the Wardrobe backend, only when you use the feature:
  - one compressed photo per garment for recognition (≤ 1600 px JPEG, background removed on device first)
  - order text or an order screenshot for import
  - garment *attributes* (ids, category, color, formality; no images) for outfit ranking
- The backend is stateless. It forwards requests to Anthropic and stores nothing. Logs contain no images, text or tokens.
- Info.plist usage strings: location (weather), camera, photo library. Local notifications need no Info.plist entry; the system asks when you turn the reminder on.
- **Profile → Export my data** writes everything to JSON. **Delete account and all data** removes every record, photo, cached ranking, notification and the session token from the device.

## Assumptions

Decisions the spec left open, with the default chosen:

1. **Platform/toolchain.** Swift 5 language mode with minimal strict-concurrency checking, to keep the first compile on a new machine simple. The engine package is concurrency-safe (`Sendable` value types) and ready for Swift 6 mode.
2. **Session tokens.** Apple identity tokens expire after about 10 minutes. After verifying one, the backend issues its own HS256 session token (30 days) instead of asking for a new Apple token on every call. The backend stays stateless.
3. **Pending-review garments are used in outfits.** The spec only excludes archived items. "Needs review" is a nudge to check the details.
4. **Slots.** Sweaters and hoodies are tops; blazers, jackets and coats are outerwear. Layering a sweater over a shirt is not modeled in the MVP. Accessories are added after the core outfit is chosen, so they don't multiply the combinations.
5. **Formality ranges.** Occasions: work 2–4, business meeting 4–5, dinner 3–5, casual outing 2–3, weekend 1–3, event 4–5, travel 1–3. Styles: formal 4–5, smart casual 3–4, casual 2–3, sporty 1–2. The outfit range is the intersection of the two; if they don't overlap, the style wins.
6. **Weather rules** (feels-like temperature). Below 10 °C a jacket or coat is required (a blazer is not enough). Coats only up to 15 °C, jackets up to 24 °C, blazers up to 28 °C. Sweaters and hoodies only up to 22 °C. Shorts only from 20 °C, and never for work, meetings, dinner or events. A day counts as rainy at ≥ 50 % precipitation; rain excludes suede, nubuck and canvas shoes.
7. **Color harmony.** A fixed 22-color palette shared by app, engine and backend. Navy, grey, charcoal, black, white, beige, cream, tan, brown, khaki, denim and light blue count as neutrals. Outfits allow at most two accent colors.
8. **Patterns.** One patterned piece, or two if one of them is striped (the "subtle" pattern) and the patterns differ.
9. **Recent wear.** Garments worn today or in the previous 2 days are skipped (`EngineConfig.recentWearExclusionDays = 3`). Pieces the user picks in the builder are exempt.
10. **AI ranking.** The engine builds a diverse shortlist of up to 30 valid candidates. The AI picks candidate ids and writes the wording. It cannot invent combinations, and both the backend and the app discard unknown ids. Results are cached per day for the same context, bucketed weather and shortlist. The AI is called only when signed in and when there is something to choose from. Builder results (including "missing" pieces) are ranked locally.
11. **Gap analysis** counts distinct new core outfits (top, bottom, shoes, optional outerwear) across each preferred style × each season, ignoring weather and recent wear. Candidate purchases come from a built-in 30-item menswear catalog (`StarterCatalog`), and anything already owned (same category and color) is skipped.
12. **Purchase directions** are deterministic: three tiers per category with typical prices in EUR, converted with fixed approximate rates (EUR, PLN, USD, GBP, CHF, SEK, CZK, DKK, NOK). Retailer links are search URLs only: Zalando (domain by region; Poland by default), Google Shopping and Allegro (with `price_to` when a budget is set).
13. **Duplicates.** Same category + primary color + brand (case-insensitive) is treated as a likely duplicate.
14. **Product images from orders** are downloaded by the app (10 s timeout, 5 MB cap, `image/*` only). The backend only passes on image URLs that literally appear in the order text, so the model can't invent links.
15. **AI model and effort.** `AI_MODEL=claude-opus-5-5` with `AI_EFFORT=low` (classification and extraction don't need deep reasoning). Requests opt into Anthropic's server-side refusal fallback.
16. **Rate limiting** is in memory, per instance: 60 AI requests per user per 10 minutes, and 20 session requests per IP per 10 minutes. Use a shared store in production (see backend README).
17. **Onboarding** counts all non-archived garments toward the 8-garment unlock and the 10-garment goal. It can be skipped.
18. **Notifications.** One repeating local notification at the chosen time. The text doesn't depend on whether outfits were already generated.

## Extension points (out of scope for the MVP)

| Future feature | Where it plugs in |
|---|---|
| iCloud / multi-device | `ModelContainerFactory` (`cloudKitDatabase`), `ImageStore` protocol. The schema already follows CloudKit's rules (defaults everywhere, no unique constraints), and records carry `ownerID`. |
| Email forwarding / mailbox import | New `PurchaseImporter` implementation |
| Affiliate feeds | New `ProductProvider` implementation |
| Android | Reuse the backend and its prompts/schemas; port `OutfitEngine` (pure logic, fully tested) |
| Calendar, virtual try-on, social, packing planner | Not started |

## Stage log

| Stage | What works | Simplified |
|---|---|---|
| 1. Skeleton | XcodeGen project, SwiftData models, Sign in with Apple, 5 tabs, debug seed | |
| 2. Backend + networking | 3 AI endpoints + session endpoint, Zod in/out, retry once, rate limits, `WardrobeAPI` client | In-memory rate limiter |
| 3. Photo add flow + Closet | Multi-select / camera, on-device cutout, AI recognition, review cards, Needs review, grid, filters, detail and edit | Several garments in one photo share the same photo (copied per garment) |
| 4. Weather + engine + Today | WeatherKit/mock + offline cache, engine with tests, 3 suggestions, wear, favorite, swap | |
| 5. Builder + favorites | Anchors, occasion/style/season, missing pieces with dashed tiles, add to shopping list | Builder is ranked locally |
| 6. Order import | Paste text, screenshot, Share Extension, image download, duplicates | |
| 7. Shop | Gap ranking, 3 tiers, search links in Safari view, budget/brand filters, wishlist, "Bought" → closet | Fixed currency rates |
| 8. Profile + polish | Preferences, stats, notifications, appearance, export, delete, onboarding, haptics, skeletons, empty/error states, README | |
