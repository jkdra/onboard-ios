# On Board First Class — Subscription Shell (Design)

- **Date:** 2026-07-29
- **Branch:** `feature/monetization`
- **Status:** Approved for planning
- **Author:** Jawad Khadra (with Claude)

## Summary

Build the **UI shell and plumbing seam** for *On Board First Class*, a premium
subscription, without wiring any real billing or any gated feature yet. The user
can open a paywall, see what First Class offers, pick a plan (Monthly / Yearly),
"subscribe" and "restore" against a **mock**, and the app tracks a single
`isFirstClass` entitlement flag that every future perk will read.

This is the load-bearing wall of monetization: the entitlement + paywall layer
is needed regardless of which perks or ad systems ship later, and it depends on
none of them.

## Scope

### In scope (this slice)
- `FirstClassView` — the full, richly-designed First Class screen, **working** (not a static mockup). Fully custom SwiftUI, **not** Apple's `SubscriptionStoreView`.
- Plan selector: Monthly / Yearly, with a free-trial badge (display only; no real trial logic yet).
- Restore button.
- Subscribed-state variant of the same view (status + Manage Subscription deep link).
- `SubscriptionService` protocol + `MockSubscriptionService` + a stubbed `StoreKitSubscriptionService`.
- `EntitlementStore` (`@Observable @MainActor`) exposing `isFirstClass` as the single future gate.
- Settings entry point: a flashy **boarding-pass hero card** in its own section **above** the Account section, as a `NavigationLink` that **pushes** `FirstClassView`.
- Butler display font bundled (heavy weights) and used for First Class display text only.
- Swift Testing coverage against the mock.

### Explicitly out of scope (deferred to later slices)
- Real StoreKit 2 purchase flow and a `.storekit` test config (next slice).
- Server-side entitlement mirror (`profiles.is_first_class`, App Store Server Notifications) — deferred until ads exist, per decision.
- Any actual **perk** implementation (Profile Colors, crop shapes, post fonts, early access, priority support).
- "Peek" at nearby boards (scaffolding only — listed as *Coming soon* in the UI).
- Promoted-content feed spine, AdMob, and Sponsored posts (separate specs).
- Contextual/in-context upsells (only the Settings entry point for now).

## Decisions locked during brainstorming

1. **Name:** *On Board First Class*.
2. **Entitlement storage:** client-side only (local, in-memory/`UserDefaults` for the mock). No server mirror yet — nothing to gate server-side until ads exist.
3. **Commercial target:** Monthly + Yearly, with a free trial. This slice renders these but does not implement real billing.
4. **Approach A:** working UI backed by a mock, behind the real service seam; real StoreKit lands later without touching the UI.
5. **Aesthetic:** stay **monochrome — no gold**. Premium signal comes from the **Butler** display serif (Fabian De Smet, free for commercial use) plus the boarding-pass / First Class / The Host motif.
6. **Restore button** is required.
7. **Entry point:** a flashy boarding-pass **hero card** in its own `Section` **above** the Account section; the card is a `NavigationLink` that **pushes** `FirstClassView` (consistent with the rest of Settings, which pushes rather than sheets).
8. **Fully custom SwiftUI view — not `SubscriptionStoreView`.** Apple's StoreKit SwiftUI views auto-handle purchase/restore but are semi-templated and can't be art-directed into the boarding-pass/Butler design; they also bind to real StoreKit product IDs, which is awkward to mock. We keep full design control with our own buttons calling the `SubscriptionService` seam; real StoreKit later calls `Product.purchase()` imperatively behind the same buttons.

## Architecture

Mirrors the existing `protocol → Mock/Live → Factory.make(configuration:)` pattern
(see `OnboardingService` / `OnboardingServiceFactory`) and the `@Observable @MainActor`
store pattern injected via `AppLaunchContext` + `.environment` in `On_BoardApp`.

### Models
- `FirstClassPlan` — `enum { case monthly, yearly }`.
- `FirstClassProduct` — `{ id, plan: FirstClassPlan, displayPrice: String, hasIntroTrial: Bool, trialDescription: String? }`. `Sendable`.
- `FirstClassPerk` — `{ icon: String (SF Symbol), title: String, blurb: String, availability: enum { available, comingSoon } }`. Data-driven so adding perks later is data, not new views.
- `EntitlementState` — `enum { case loading, loaded(products:[FirstClassProduct]), purchasing, subscribed(renewalNote:String?), failed }`.

### Service
```swift
protocol SubscriptionService: Sendable {
    func loadProducts() async throws -> [FirstClassProduct]
    func purchase(_ product: FirstClassProduct) async throws -> EntitlementState
    func restore() async throws -> EntitlementState
    func currentEntitlement() async -> EntitlementState
}
```
- `MockSubscriptionService` — returns a fake Monthly + Yearly product (Yearly flagged best value, both with a trial). `purchase`/`restore` flip entitlement to `.subscribed`. A `simulateFailure` switch exercises the error path. Persists the mock "subscribed" flag to `UserDefaults` **for dev only**, so relaunch still shows the subscribed UI.
- `StoreKitSubscriptionService` — **stub** with TODOs; real StoreKit 2 in the next slice.
- `SubscriptionServiceFactory.make(configuration:)` — returns the mock for now. **Note:** unlike the other factories this does *not* branch on `isSupabaseConfigured` (StoreKit needs a StoreKit config, not Supabase); a documented TODO marks where the live branch goes.

### Store
- `EntitlementStore` (`@Observable @MainActor`): holds `isFirstClass: Bool`, `products: [FirstClassProduct]`, `state: EntitlementState`. Methods: `loadProducts()`, `purchase(_:)`, `restore()`. Injected via `AppLaunchContext.makeEntitlementStore()` + `.environment` alongside the other stores.
- `isFirstClass` is the **single gate** every future perk reads. Nothing else should re-derive subscription status.

## UI

### Entry point — the boarding-pass hero card
A dedicated `Section` in `SettingsView` placed **above** `accountSection`, containing a single full-bleed **boarding-pass hero card** (not a plain row). The card is a `NavigationLink` that **pushes** `FirstClassView`.

Design of the card:
- **Inverted for contrast:** a black ticket card on the light Form in light mode (white Butler title, subtle grayscale gradient for depth); flips to a light card in dark mode. The high-contrast inversion is what makes it pop off the settings list — flashy through contrast/elevation, not color.
- **Boarding-pass motif:** perforated ticket edge, a small ✈ / "ON BOARD" eyebrow, The Host peeking in a corner. "First Class" set in **Butler**; tagline ("Skip the ads. Unlock the good stuff.") in system font.
- **Full-bleed rendering inside `Form`:** the section row uses `.listRowInsets(EdgeInsets())` + `.listRowBackground(.clear)` so the card paints itself edge-to-edge instead of sitting in default row chrome.
- **Subscribed state:** the card becomes a *membership pass* — "First Class ✈️ · renews …" — so it stays meaningful post-purchase instead of nagging.
- **Accessibility:** it's a real `NavigationLink`/`Button` with an explicit accessibility label ("On Board First Class, subscribe" / "On Board First Class, membership") — a self-painted card is not automatically accessible.
- **Animation caveat:** any shine/shimmer is **finite or tap-triggered, never `repeatForever`** — a perpetual animation keeps the app non-idle and makes XCUITest flaky.

### `FirstClassView` (pushed destination)
Vertical scroll, sections top to bottom:
1. **Hero** — "On Board First Class" set in **Butler** (display), boarding-pass / First Class motif with The Host. Monochrome.
2. **Perk list** — data-driven from `[FirstClassPerk]`, each a `Label`-style row (SF Symbol + title + blurb in the system `.fontStyle` body). Perks: Ad-free (sponsored posts stay), Profile Colors, Custom crop shapes, Post fonts, Early access, Priority support, and **Peek — "Coming soon"** badge.
3. **Plan selector** — Monthly / Yearly cards; Yearly flagged "Best value"; a **"Start with your free trial"** badge. Plan names in Butler; prices/details in system font.
4. **CTA** — `.buttonStyle(.boardPrimary)` + `LoadingButtonLabel` while `.purchasing`.
5. **Restore** — text button, calls `store.restore()`.
6. **Legal** — Terms / Privacy links + the auto-renewing-subscription disclosure line Apple requires on subscription paywalls.

### Subscribed state
The same view, when `isFirstClass == true`, flips to a confirmation: "You're First Class ✈️" (Butler), renewal note, and a **Manage Subscription** button that deep-links to the system subscription sheet. No plan selector / CTA in this state.

## Data flow
`FirstClassView` appears (pushed from the hero card) → `EntitlementStore.loadProducts()` (mock returns instantly) → render `.loaded`. Select plan → tap CTA → `.purchasing` → `purchase()` → mock flips `isFirstClass` → animate to subscribed state. Restore mirrors this. No network; mock state persists to `UserDefaults` for dev only.

## Error handling
Purchase/restore failures route through the app's `PresentableAlertError` / `alertError` pattern — consistent with `PhotoAttachmentController` et al. Never fail a purchase/restore silently. The mock's `simulateFailure` switch drives the tested failure path.

## Butler font integration
- **Standard, not Stencil** (decided 2026-07-29). Stencil's stroke breaks get fragile at small sizes and under Dynamic Type / low-vision, and read industrial/cargo rather than luxury. Standard Butler's solid high-contrast Didone is the "First Class" luxury cue.
- **Source on hand:** `~/Downloads/Butler/Butler FREE/OTF - best in most cases/` — the standard free family, 7 OTF weights (Light, Roman, Medium, SemiBold, Bold, ExtraBold, Black). Free for commercial use (Fabian De Smet). We bundle only what we use: **Black** (`Butler-Free-Blk.otf`) for the big "First Class" title and **Medium** (`Butler-Free-Med.otf`) for plan names / eyebrow; skip the rest to keep app size down. (Ignore the `._`-prefixed AppleDouble twins; the Stencil set and Butler Pro upsell are unused.)
- Bundle the chosen `.otf` weights into the app target; register via `UIAppFonts` in `On-Board-Info.plist`. Keep a copy of the license text next to the font files for provenance.
- Wrap usage in a small `Font+FirstClass` helper (e.g. `Font.firstClassTitle`) so call sites are one clean call.
- **Display-only:** hero wordmark, plan names, section titles. Body and perk descriptions stay in the app's system `.fontStyle` — high-contrast serifs hurt legibility at small sizes and in long runs.
- **Dynamic Type:** load via `UIFontMetrics`-scaled `Font.custom(...)` so First Class display text grows with the user's text size; system serif is the fallback.

## Testing (Swift Testing, against the mock)
- `loadProducts()` returns exactly two plans (Monthly, Yearly), both with a trial.
- `purchase()` flips `isFirstClass` to `true` and yields `.subscribed`.
- `restore()` restores `.subscribed`.
- `simulateFailure` surfaces an error (no silent failure) and leaves `isFirstClass` unchanged.
- `EntitlementStore` state transitions: `.loading → .loaded → .purchasing → .subscribed`.

## Pre-ship checklist (NOT this slice — bank for when we submit)
- **Apple requires an IAP to deliver real value.** Before submitting, light up at least one real perk — cheapest is **Profile Colors** (pure client, no backend, no ad dependency). The gate is left ready by this slice.
- Verify Butler's license explicitly permits app **embedding** (design-use confirmed; keep the license file in-repo).
- Create the real subscription products in App Store Connect; swap placeholder prices.
- Add the real `.storekit` test config + `StoreKitSubscriptionService` (next slice).
- Confirm the auto-renew disclosure copy matches Apple's current requirements.
- **EULA link placement in App Store Connect** (researched 2026-07-29, cross-corroborated across multiple independent Apple Developer Forum threads): if using the standard Apple EULA, link it in the App Description; if using a custom EULA, attach it via App Store Connect's license-agreement field instead. Missing either, in either location, is one of the single most common documented 3.1.2 rejection reasons — independent of whether the in-app paywall discloses pricing/terms correctly.
- **Never add a toggle that turns the free trial on/off independently of plan selection.** Apple began actively rejecting this exact pattern under 3.1.2 starting mid-January 2026 ("confusing... may prevent users from understanding they are committing to an auto-renewing subscription"), confirmed across multiple independent paywall-tooling vendors. Not a risk today — `FirstClassView`'s plan picker is two selectable cards (Monthly/Yearly), each bundling its own trial info, not a toggle layered on top of plan choice — but do not introduce one later.

## Open items
- Exact SF Symbol for the Settings row and the boarding-pass motif (design detail, resolve during implementation).
- Final placeholder prices for the mock (any values; real numbers come from App Store Connect later).

## Addendum (2026-07-29, same day): AdMob SDK groundwork + the Ad-Free gate

Ahead of the "Sponsored posts + AdMob" slice, the real Google Mobile Ads SDK was added now so the Ad-Free perk has something concrete to gate:
- **Dependency**: `https://github.com/googleads/swift-package-manager-google-mobile-ads.git` (the Google-maintained SPM package; verified via WebSearch/WebFetch against Google's own docs and GitHub repo, not guessed), pinned `upToNextMajorVersion` from `13.7.0`. Pulls in `GoogleUserMessagingPlatform` (Google's UMP consent SDK) automatically as a transitive dependency — useful groundwork for the EEA/UK/Switzerland consent flow later, not wired yet.
- **`MobileAds.shared.start()`** called once in `On_BoardApp.init()` (SDK init only — loads/shows nothing). `GADApplicationIdentifier` in Info.plist is currently Google's **public test App ID** (`ca-app-pub-3940256099942544~1458002511`) — must be swapped for the real AdMob App ID before shipping ads. `NSUserTrackingUsageDescription` added (required once ATT is requested, not yet wired).
- **`AdsGateway`** (`On Board/Monetization/AdsGateway.swift`) is the single gate every future ad-load call site must check: `isEligibleForAds` is `false` whenever `EntitlementStore.isFirstClass` is `true`. Injected the same way as the other stores (`AppLaunchContext.makeAdsGateway`, `.environment(ads)`) — **shares the app's one `EntitlementStore` instance**, not a second disconnected one (a real bug caught and fixed during this pass). No actual native-ad loading/rendering exists yet — that's the feed spine, still a separate future slice.
- **Pre-ship, not yet done**: the SDK itself warns at runtime that ~50 `SKAdNetworkItems` are missing from Info.plist (needed for ad-attribution measurement) — add Google's official recommended list before ads actually go live. Sponsored posts (paid local-business placements) are explicitly NOT gated by `AdsGateway` — they stay for First Class members too, per the perk's own copy.

## Addendum (2026-07-29, same day): Profile Colors — the first real (not just listed) perk

Per the pre-ship checklist above, **Profile Colors** is now actually wired, not just advertised:
- **`ProfileColor`** (`On Board/Monetization/ProfileColor.swift`) — 6 accent options + none, pure client-side.
- **Deliberately client-side, per-device only** — stored via `@AppStorage("profileColor")`, no `Profile`/Supabase field, no migration. Matches the codebase's existing precedent for this kind of un-synced local preference (the profanity setting, documented in this file's Onboarding section). **Real limitation, not hidden**: only the owning device sees the tint — it does not sync to other users' views of your profile yet. That needs a synced `profiles` column, a clearly separate future step.
- **Render**: `AvatarView` gained an optional `tint: Color?` param (a thicker accent ring in place of the default neutral one). Only ever passed for the signed-in user's own avatar (`ProfileReadContent`'s `canEdit` check + `entitlement.isFirstClass`) — other people's `AvatarView` instances never receive a tint, so there's no per-avatar entitlement lookup scattered through the feed.
- **Picker**: `ProfileEditContent` gained a `profileColorSection` — First Class members get a 7-swatch picker; non-members get a locked row ("Profile Color — First Class") that pushes `FirstClassView`, turning a moment of "I can't do that" directly into the upsell.
