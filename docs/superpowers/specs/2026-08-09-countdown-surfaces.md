# Countdown Surfaces — Live Activity + Small Widget (parked 2026-08-09)

Concept mockups (approved, iterated with Jawad): 
https://claude.ai/code/artifact/8ff16642-481f-42bd-b63c-0ab287920c15

Deliberately NOT built yet. Prerequisites on Jawad before any code:
1. **App Group** `group.org.onboardapp.onboard` enabled on both App IDs in
   the developer portal (simulator works without; device/TestFlight won't).
2. **Widget extension target** created in Xcode (File → New → Target →
   Widget Extension, named `BoardWidgets`, "Include Live Activity" checked).
   Hand-authoring an embedded signed target into pbxproj was considered and
   rejected as the riskiest mechanical op available.

## Scope decisions (settled — don't relitigate)

- **v1 ships the SMALL widget only.** Medium (mini-masonry) is designed in
  the mockup but explicitly deferred.
- **Live Activity starts at T−3h before the weekly clear, foreground-only**:
  if the app is opened (or open) inside the window, start it. APNs
  push-to-start (guaranteed delivery; needs a cron trigger + a
  `send-notifications` case + push-to-start token registry) is the v2
  upgrade, not v1.
- **Count = "new posts since last seen"** (`last_seen_at`, same basis the
  re-engagement pushes call unseen). Client computes from cached feed +
  last-seen; updates on app refresh/foreground. Copy is "12 new posts",
  pluralized via automatic grammar agreement
  (`^[\(count) new post](inflect: true)`), never a hand-rolled ternary.

## Design contract (from the approved mockup)

- **Monochrome.** The brand is monochrome; tones belong to posts only. The
  progress bar is ink (`currentColor`), not a tone gradient.
- **The Host is the attribution.** No "On Board ·" prefix anywhere — the
  subtitle line is the campus name alone (`currentBoard.name`); tight slots
  use `Board.displayShortName` (column live + backfilled: IVC, UCI, CSUF,
  CSULB, SC, CPP; `list_accessible_boards` returns it; `Board.shortName`
  already decoded client-side). The Host stands free — never boxed in an
  app-icon tile.
- **Every text block is one-line clamped** (`.lineLimit(1)` +
  `.truncationMode(.tail)` on title, subtitle, count line, widget captions).
- **Banner composition** (Lock Screen + expanded Dynamic Island identical):
  Host glyph | "Clears Tonight" over campus name | tabular countdown →
  ink progress bar → "12 new posts" / "gone at midnight" row.
- **Compact Dynamic Island shows only the nearest unit**: hours until the
  final hour ("3h"), then minutes ("47m").
- **Small widget**: "Clears in" eyebrow, countdown, count caption, and the
  Host peeking from the corner **exactly per the CountdownCard recipe**
  (bottom-corner anchor hung past the edge, **12% opacity watermark**,
  clipped by bounds, color-inverted on dark). Slightly larger and more
  inset than the card's (84px at 170pt, right −6 / bottom −13). Full
  opacity was tried and rejected — watermark everywhere is the rule
  ("the Host on ambient surfaces is always a 12% corner watermark").
- Typography: ZalandoSansExpanded for countdowns/display, SemiExpanded for
  body. Light + dark variants both required (iOS 18 tinted comes free from
  monochrome).

## Implementation notes (from the concept page)

- Countdown ticks via `Text(timerInterval:)` — free, battery-neutral; only
  the unseen count needs ActivityKit updates (app-foreground driven in v1;
  piggyback the 15-min digest query if/when push updates arrive).
- `staleDate` at the clear; dismiss on the Monday-reset push; tap deep-links
  through the existing `onboard://` route.
- Widget `TimelineProvider`: hourly entries, every 15 min inside the final
  4 hours. Data crosses via App Group storage the app writes on refresh
  (week end, unseen count, campus short name). Monday flip state: "New
  board — be the first."
- `NSSupportsLiveActivities` in the app plist; ActivityAttributes type
  shared between targets.

## Related but shippable independently

- The five cron pushes rewritten in The Host's voice ("clearing-soon" as
  the save-tier push) — polish research's highest ROI-per-hour item, pure
  server-side copy, no client dependency.
