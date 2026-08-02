# Ads & Monetization Roadmap (Design / Reference)

- **Date:** 2026-07-30
- **Branch:** `feature/monetization`
- **Status:** Reference — decisions captured, implementation plan not yet written
- **Author:** Jawad Khadra (with Claude)

## Summary

Captures the strategy, policy constraints, and privacy stance for On Board's
advertising system, plus the sequencing decision that **First Class + AdMob ship
first** and **Sponsored posts (our own native ad system) are deferred**.

This is a decisions document, not a task plan. Several choices are still open
(see [Open decisions](#open-decisions)); a `docs/superpowers/plans/` plan should
be written once they're settled.

## Current state (as of 2026-07-30)

Built and on `feature/monetization`:

- `Monetization/AdsGateway.swift` — the single entitlement gate. `isEligibleForAds`
  is `false` for First Class members. No real ad loading yet.
- `Monetization/EntitlementStore.swift` — `isFirstClass`, the single gate all perks read.
- `Monetization/SubscriptionService.swift` + `MockSubscriptionService` + stubbed
  `StoreKitSubscriptionService`.
- `Views/Monetization/FirstClassView.swift`, `FirstClassBoardingPassCard.swift`.
- Google Mobile Ads SDK resolved as a Swift Package dependency
  (`swift-package-manager-google-mobile-ads`); GoogleUserMessagingPlatform comes
  along transitively.
- `GADApplicationIdentifier` present in `On-Board-Info.plist`.

Not built: any actual ad load or render, the promoted-content feed spine, the
UMP consent flow, real StoreKit billing, any First Class perk beyond the flag.

## Sequencing decision

**Phase 1 (now): First Class + AdMob native ads.**
**Phase 2 (deferred): Sponsored posts.**

Sponsored posts are deferred because they are not really an ads feature — they
are a whole second product. They require a business-facing portal for designing
posts, business account types distinct from student profiles, permissions to
serve a placement across multiple campuses, and a metrics/reporting surface.
None of that exists.

**Consequence to accept up front:** Phase 1 revenue will look unimpressive, and
that is expected, not a signal of the ceiling. All of On Board's genuinely
valuable targeting data (major, graduation year, interest graph, follow graph)
is unusable by AdMob — see [Targeting & privacy](#targeting--privacy). Phase 1 is
contextual-only monetization. The first-party data becomes revenue in Phase 2.

## Ad network strategy

**AdMob is the primary and only integration.** Meta Audience Network is *not* a
parallel SDK and should never be integrated directly. On iOS it is only worth
running as a **bidder inside AdMob mediation**, where Meta's demand competes
against Google's per impression through the adapter we already have a path to.

Rationale: Audience Network's advantage was cross-app tracking, which App
Tracking Transparency (2021) removed. Its iOS payouts and fill collapsed and Meta
has deprioritized the product. Google's demand pool is broader and fills reliably.

Practical effect: one renderer, one gateway, one code path. `AdsGateway` stays
correct — adding Meta later is a mediation config change, not a second gate.

## Format decision: native ads only

**No interstitials. No banners.**

Interstitials and banners render Google's own chrome and cannot be restyled at
all. Native Advanced is the only format that can be art-directed to match On
Board's design language, which makes it the only format compatible with the
app's visual standard. This matches the `TODO(admob-spine)` already written into
`AdsGateway.swift`.

## Hard policy constraints (native advanced, iOS)

These are non-negotiable and shape the design. Verified against Google's docs
2026-07-30.

1. **Wrapper.** The ad must be inside a `GADNativeAdView`, with every asset view
   registered as an outlet on it. The SDK records impressions and clicks itself.
2. **Forbidden:** custom click handling; modifying or overlaying ad assets;
   enabling user interaction on clickable views (especially the CTA).
3. **Always render:** headline and media (via `GADMediaView`).
   **Conditionally render (only when present):** body, icon, call-to-action,
   advertiser name, star rating, store, price.
4. **Ad attribution is ours to draw.** We must render "Ad", "Advertisement", or
   "Sponsored" (localized), **minimum 15pt in both dimensions**, **at the top of
   the ad**. Google does not draw this for us.
5. **AdChoices reserve zone.** The SDK auto-inserts the AdChoices overlay into a
   corner. We must leave it clear space, and the background behind it must keep
   it easily visible.
6. **The attribution badge must not overlap the AdChoices overlay**, and neither
   may be hidden, obscured, or camouflaged.

## AdChoices customization — what is and isn't possible

**The icon itself cannot be restyled.** It is the DAA self-regulatory mark, not
our asset. Policy forbids modifying, resizing, recoloring, replacing, obscuring,
or camouflaging it. Treat it like a system control (in the spirit of the Apple
Pay button): compose *around* it, don't reskin it.

What we *can* control:

- **Which corner** — `GADNativeAdViewAdOptions.preferredAdChoicesPosition`, one of
  four corners. Defaults to top-right if unset.
- **Arbitrary placement** — instantiate a `GADAdChoicesView` and assign it to
  `nativeAdView.adChoicesView`. **Caveat: this is access-limited and requires
  going through a Google account manager**, so assume it is unavailable to us at
  launch and design for the four-corner API.
- **What it sits on** — we choose the backdrop colour/material. Policy *requires*
  we pick one that keeps the icon clearly visible, so this is a contrast
  obligation as much as a design lever. Giving the icon a deliberate neutral chip
  of our own drawing is the way to make a foreign element look intentional.

Under Meta mediation the adapter owns AdChoices rendering; the AdMob Meta adapter
exposes a `backgroundShown` toggle via network extras. Known issue to design
around: Meta's AdChoices icon has historically rendered out of bounds in tight
custom layouts — leave real padding in that corner.

## Custom ad card design direction

Decided direction, not yet mocked up:

- **Attribution label:** a prominent banner reading **"Advertisement"** in the
  app's own font (Butler or the body face — TBD in the mockup), at the top of the
  card. Wording and placement are both explicitly compliant.
- **Placement split:** attribution **top-leading**, AdChoices **top-trailing**
  (the SDK default corner), so they cannot collide.
- **The banner must sit above the asset area**, not painted over the media —
  overlaying assets is prohibited.
- **Alternative variant to mock:** a corner capsule paired with a slightly
  thickened card border, instead of a full-width banner.
- Minimum 15pt on the badge in both dimensions.

## Ad experience principles

The governing tension: ads must not degrade the experience, but must be
**felt** — otherwise removing them isn't worth paying for.

**These are separate axes, and conflating them is the trap.** Salience is not
what makes ads hated. What makes them hated is interruption, motion and sound,
accidental taps, layout shift, repetition, and irrelevance. A large, obvious,
honestly-labelled ad that costs the user nothing to scroll past is not annoying.
A small tasteful banner that shifts the feed while it loads is. So the target is
**high visual salience, near-zero interaction cost** — which is exactly what the
"Advertisement" banner design buys us.

### The perk is chromatic, not quantitative

On Board's feed is a masonry grid of **tone-coloured** cards — colour is the
board's identity. That gives us a lever most apps don't have: an ad card can sit
**outside the board palette** (neutral/desaturated card + the attribution band)
rather than borrowing a post tone. It reads instantly as not-a-student-post
without being ugly, and it means a First Class feed is *chromatically coherent*
in a way the free feed isn't.

That reframes the pitch. Not "fewer ads" but **"your board is only your campus
again."** On a community bulletin board that is a real emotional proposition,
and it lets us make ads visible without making them irritating.

### Sparse and obvious beats dense and subtle

Sparse-but-visible wins on both axes at once: better experience *and* a sharper
contrast when they disappear. Recommended defaults (see Open decisions):

- ~1 ad per 8–12 masonry cards.
- Never two ads in one viewport.
- Never in the first viewport of a board.
- Session cap around 4–6 impressions.

### The never-list

Protect the moments that define the product:

- No interstitials, ever. No autoplay video, no sound.
- No ads in `PostDetailView` — the reading surface stays clean.
- No ads in comment threads.
- No ads during onboarding, or in a user's first session.
- No ads on the archive.

### Ad content standards (Phase 1 — not optional)

The audience is 17–22 year olds, a meaningful share of them minors or under 21.
Before the first ad renders:

- Set `GADRequestConfiguration.maxAdContentRating` to a rating appropriate for a
  mixed-age student audience.
- Use AdMob's console blocking controls to block sensitive categories —
  alcohol, tobacco/vaping, gambling, payday and short-term lending, dating,
  adult content — rather than relying on the rating alone.

Serving an alcohol or sportsbook ad to a 17-year-old freshman on a campus board
is both a compliance problem and exactly the kind of story that ends a campus
app's reputation.

### Sponsored post advertiser policy (Phase 2)

Owner's rules, as stated 2026-07-30. Stricter than the user-content moderation
policy **by design** — paid speech gets less latitude than community speech,
which is a normal and defensible platform position.

1. **No drugs or alcohol.** Includes cannabis (regardless of state legality),
   nicotine and vaping, and gray-market intoxicants (kratom, delta-8).
2. **No illegal activity** — illegal federally or in the campus's state.
3. **No promotion of political ideologies or ideals.** Scoped as: no candidates,
   parties, ballot measures, PACs, or issue advocacy.
4. **No promotion of religion or irreligion.** The ban is on actively promoting
   *conversion* — proselytizing, recruitment to belief, or advocacy for atheism.
   A business **aligned with** religious values is explicitly fine: halal
   restaurants, kosher delis, and church-run shops advertise like anyone else.
   The test is whether the ad sells a product or sells a belief.
5. **No gambling or sports betting. Full stop.**
6. **Audience must be the student reading it.** No ads aimed at businesses —
   audience-based, not business-model-based. A B2B software company advertising
   *internships to students* is fine and welcome; a consumer brand advertising
   *to franchise owners* is not.

Additional prohibited categories (standard, and campus-specific ones generic
policies miss):

- Essay mills and contract-cheating services. Academic-integrity poison and an
  instant relationship-ender with any university.
- Multi-level marketing and "campus ambassador" recruitment schemes.
- Payday and short-term lending; credit card solicitation (campus-specific legal
  restrictions apply — needs legal review before ever allowing it).
- Adult content and dating.
- Weapons.
- Crypto trading, and get-rich-quick / trading-education offers.

**Resolved edge cases** (decided 2026-07-30):

- **Bars and breweries — allowed, alcohol is not.** The venue may advertise
  itself and its non-alcohol offering (trivia night, live music, food, coffee),
  but no drink specials, no alcohol imagery, no alcohol pricing. Blanket-banning
  venues would cost real revenue, since a large share of campus-adjacent
  advertisers are bars.
- **Religiously affiliated businesses — allowed.** See rule 4.
- **Employers, internships, housing, grad programs — allowed and welcome.**
  Among the most relevant, highest-value inventory on a campus board.

### Recruiting ads must be transparent

Job and internship listings are the single biggest fraud vector aimed at
students — unpaid commission-only "sales internships", MLM recruitment dressed
as an internship, fake-recruiter phishing, and application-fee scams all target
campuses specifically. "Transparent" therefore needs teeth. Required on any
recruiting sponsor post:

The **job & internship sponsor type** enforces these as required schema fields,
so a non-compliant listing cannot be submitted at all:

| Field | Rule |
|---|---|
| `brandName` | Required. The actual employer's brand/legal entity. No unnamed "a fast-growing startup". Must match the verified advertiser account, or see `postingOnBehalfOf`. |
| `postingOnBehalfOf` | Required when a third-party recruiter posts for a client — names the client, and the client's brand is what renders on the card. |
| `payType` | Required enum: hourly / salaried / stipend / unpaid. Commission-only is its own value and may **not** be labelled an internship. |
| `payRange` + `payPeriod` | Required whenever `payType` is paid. Structured numbers, not prose, so an empty or evasive value is rejectable. |
| `responsibilities` | Required list, **minimum 3 entries**, covering *all* potential duties. Blocks both vagueness and bait-and-switch ("marketing" that turns out to be door-to-door sales). |
| `brandURL` | Required. Must resolve on the employer's **own registered domain**. |
| — | No application fees, deposits, or required purchases, ever. |

Two of these carry more weight than they look:

- **`brandURL` domain validation is the cheapest high-signal check we have.**
  Auto-reject link shorteners, free form builders (Google Forms, Typeform),
  Linktree-style aggregators, and bare social profiles. Require the domain to
  correspond to `brandName`. A large share of scam and MLM postings die here
  without a human ever reading them.
- **Structured pay fields, not prose.** Beyond anti-fraud, a growing number of
  US states now require pay ranges in job postings; making the field mandatory
  means On Board is never the vector for a non-compliant listing.

Requiring *all* responsibilities is also the single most effective anti-MLM
field: a legitimate employer can list duties in thirty seconds, and a recruiter
whose actual job is "recruit more recruiters" cannot write them down without
disclosing it.

**MLM postings are banned on suspicion, not on proof.** MLM recruiting never
identifies itself, so a rule alone catches nothing — it needs detection signals
and a low bar to act. Reject on any combination of:

- Vague role titles with no employer: "brand ambassador", "marketing rep",
  "business partner", "financial representative", "entrepreneur".
- Commission-only pay, "unlimited earning potential", "be your own boss".
- Any required purchase — starter kit, inventory, training, certification, or a
  "small investment".
- Team-building or recruitment framing: "build your own team", residual or
  passive income, downline language.
- The named entity turning out to be an independent distributor rather than the
  brand itself.
- Sector tells: insurance sales, wellness supplements, cosmetics, essential
  oils, "financial education".

Two structural defenses matter more than reviewer vigilance:

1. **Verify the advertiser, not just the ad.** Require a registered business
   entity and a business-domain email to open an advertiser account. MLM
   distributors are individuals, so this filters most of them before they can
   ever compose a post.
2. **Reserve an unconditional right to reject** in the advertiser terms, so a
   suspicion-based rejection never has to be justified or litigated. Paid
   placement is a privilege we extend, not a service anyone is owed.

Pair both with a documented appeal path — rejection on suspicion will
occasionally catch a legitimate employer, and they need recourse.

### Positioning: hub, not destination

On Board is **not** building a jobs product, an events product, or a housing
product. The thesis is that campus life is fragmented across Fizz, Instagram,
Remind, Handshake, and a dozen university portals, and that a weekly campus
board is the natural **hub** — it surfaces what's happening and relays out to
whoever handles the transaction.

That makes every sponsor type a **discovery surface, not a destination**:

- Handshake and LinkedIn are *intent* platforms — students go there already
  looking. On Board is an *attention* platform, reaching the sophomore who
  hasn't started thinking about internships yet. Same demand-generation vs.
  demand-harvesting split as Meta vs. Google Search.
- **The weekly board reset enforces this architecturally.** A post that clears on
  Monday cannot be a job board, so sponsored posts are structurally obliged to be
  pointers. This is why `brandURL` is a required field rather than a nicety.

**Scope discipline:** the job & internship type is optimized for *"is this worth
a click"*, never for application completeness. Explicitly out of scope, forever:
saved searches, application tracking, resume storage, employer search over
student profiles, interview scheduling. Drifting into those means competing with
Handshake's institutional moat, which is not our business.

Note the identity model is what makes the whole ad business possible: Fizz's
anonymity is structurally hostile to local advertisers (brand safety), while
On Board's authored-but-quiet handles plus campus-email verification give a
verified, campus-scoped, brand-safe audience. That's the moat, not the feed.

### Sponsor types (structural, not just policy)

Sponsored posts are **typed**, not freeform creative. An advertiser picks a
sponsor type and fills that type's fields; the app renders the card. This is the
mechanism that makes several earlier commitments enforceable instead of
aspirational:

- **It enforces "belongs, not outshines."** Advertisers fill fields rather than
  upload a designed image, so the template — not the budget — controls the
  visual result. Money cannot buy a better-looking card than a student's.
- **It makes policy structural.** The food/drink type simply has no field for
  drink specials, so "no alcohol" stops being a reviewer judgment call. The
  recruiting type makes employer name and pay disclosure *required fields*, so a
  non-transparent listing cannot be submitted at all.
- **It makes moderation tractable.** Typed fields are checkable by the existing
  LLM-judge tier; freeform creative is not.
- **It simplifies the business portal.** Type-specific forms are far easier to
  build and to explain than a general-purpose design tool.

Candidate types to design (not final): local business / food & drink, event,
job & internship, housing, service, campus org. Each gets its own required field
set, its own card layout, and its own type-specific policy checks.

**Enforcement:** these rules go in the advertiser terms with an explicit right to
reject creative and refund, plus human review before a sponsored post runs. The
existing automated LLM-judge moderation tier should screen advertiser creative
too rather than building a second system.

### Engineering obligations that are really UX obligations

- **Reserve the slot's height before the ad resolves.** Layout shift in a masonry
  grid is the single most-hated failure mode and it is entirely our choice. Fixed
  slot height, neutral placeholder, no reflow.
- **Unfilled inventory becomes a First Class house promo** rather than a collapsed
  gap — converting dead slots into subscription marketing, which is the flywheel.
- **Frequency-cap per advertiser**, not just per session. The same ad six times is
  what people actually remember as "this app is full of ads."

### Sponsored posts must belong, not outshine

Phase 2 caution: sponsored posts should look **native**, not **nicer**. If a paid
local-business card is the best-looking thing on the board, students learn that
money buys visual privilege on their own bulletin board, which corrodes the
premise of the app. Target: same card language, clearly marked, never out-designed
against student content.

### How we'll know we got it wrong

Watch session length and post-open rate across the ads launch, not eCPM alone. If
engagement drops, density is too high regardless of what revenue says.

## Targeting & privacy

### Stance: no ATT prompt, ever, in Phase 1

Apple's definition (from Apple's User Privacy and Data Use page):

> "Tracking refers to the act of linking user or device data collected from your
> app with user or device data collected from other companies' apps, websites, or
> offline properties for targeted advertising or advertising measurement purposes.
> Tracking also refers to sharing user or device data with data brokers."

The load-bearing words are **"other companies'"**. Using our own in-app data to
decide which ad a student sees is **not tracking** and needs no prompt and no
IDFA. What crosses the line is handing user-level signals to a third-party
network so *they* can target.

### The three-tier model

1. **Direct-sold sponsored posts, targeted on our own backend** — Phase 2. This
   is where the first-party data earns money, we keep 100% instead of ~68%, and
   we can sell targeting Meta can no longer offer post-ATT.
2. **Contextual signals into AdMob** — Phase 1. `GADRequest` accepts `keywords`
   and `contentURL`; feed it the board's tags and surrounding post topics. This
   is contextual, not behavioural, so it stays ATT-free while still lifting eCPM
   over a blank request.
3. **AdMob (plus Meta as a bidder) as backfill**, running non-personalized ads.
   Lower eCPM, zero consent burden, no prompt.

### Rules to hold to

- **Never send user-level segments to Google or Meta.** No PII, no email hashes,
  no IDFA. Board/post context only.
- **Cohort minimum for Phase 2 targeting.** On a campus with a few hundred users,
  "graduating 2029 + follows the ski club + likes food posts" identifies one
  person. Enforce a k-anonymity floor (start at 50) before a sponsored placement
  may target a segment. This is both an ethics and a regulatory guardrail.
- **Use the age data we already have for compliance, not just targeting.** Set
  `tagForUnderAgeOfConsent` via `GADRequestConfiguration` for EU users under 16,
  and identify under-18 users (17-year-old freshmen are real) who carry stricter
  ad-personalization obligations. Knowing exact age is a compliance asset.
- Install/conversion measurement goes through SKAdNetwork / AdAttributionKit,
  which needs no prompt.

## Naming (parked)

Discussed and **deliberately not decided** — revisit when Phase 2 starts.

**Business-facing portal.** Recommendation: **On Board for Business**, not a
separate brand. The brand equity is in On Board; a local advertiser wants to
advertise *on On Board*, and a second name costs a second marketing surface,
domain, and trust story for no gain. This is why it's TikTok for Business and
Reddit Ads rather than unrelated names.

Rejected candidates and why:

| Candidate | Verdict |
|---|---|
| **On Sight** | **Onsight** is a registered Librestream trademark (US/EU/CA) on an enterprise B2B software platform. Also a homophone trap — buyers type "onsite", itself a live ad-industry term. |
| **On Campus** | [OnCampus Advertising](https://oncampusadvertising.com/) has sold exactly this (brands reaching students on 2,500+ campuses) since 2003. Direct category collision. |
| **On Business** | Has a real double meaning we initially missed — "standing on business" is Gen Z for being serious and following through. But the slang lands on *students*, and this portal's readers are local business owners; and slang has a half-life a B2B name doesn't. |
| **On Biz** | `.biz` carries a spam association, and it destroys the slang payload (nobody says "stands on biz"). Rule out. |
| **On Brand** | Taken by a fashion product-development platform. |
| **On Deck** | Taken twice — the On Deck fellowship network and OnDeck Capital. |

**Worth banking:** "on business" as *student-facing* copy — a Host line, a Pop
Score tier, a First Class perk name — where the slang hits people who speak it
and aging out costs a copy edit rather than a rebrand.

**Internal admin portal.** Currently web-only. If renamed into the family:
**On Watch** (nautical, concrete, no trademark, reads as stewardship) or
**Back of House** (restaurant term for the staff-only area; warm rather than
militaristic, and pairs with The Host's hospitality metaphor).

Rejected: **On Line** (generic, unsearchable, no pun payload, breaks in speech).
**Overwatch** — semantically apt and funny, and trademark risk is low for a
purely internal tool, but it collides with CrowdStrike's Falcon OverWatch in our
actual software category, it can never be made public, and "internal surveillance
system called Overwatch" is a bad leak headline for a campus app built on trust.

## Open decisions

These block writing the implementation plan:

1. **Ad density** — how many posts between ad slots in the masonry grid.
   Recommended default: 1 per 8–12 cards, never in the first viewport, session
   cap 4–6. See [Ad experience principles](#ad-experience-principles).
2. **AdMob vs. Google Ad Manager free tier** — GAM costs more setup now but
   plumbs the direct-sold path for Phase 2 through the same SDK and the same
   `GADNativeAdView`. Choosing raw AdMob now means a migration later.
3. **Who sees ads** — signed-out users, first-session users, or only established
   accounts.
4. Which font the "Advertisement" label uses (Butler vs. body face).

## References

- [AdMob native advanced rendering (iOS)](https://developers.google.com/admob/ios/native/advanced)
- [AdMob native ad options / AdChoices](https://developers.google.com/admob/ios/native/options)
- [AdMob native ads policy overview](https://support.google.com/admob/answer/6239795)
- [Programmatic native ads — attribution & AdChoices rules](https://support.google.com/admanager/answer/7031536)
- [Meta Audience Network via AdMob mediation (iOS)](https://developers.google.com/admob/ios/mediation/meta)
- [Meta Audience Network native ads (iOS)](https://developers.facebook.com/docs/audience-network/setting-up/ad-setup/ios/native/)
- [Apple — User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Ad Manager targeting (PPID, key-values, PPS)](https://developers.google.com/ad-manager/mobile-ads-sdk/ios/targeting)
