# Shareability — notes & post-share proposal (2026-08-10)

Goal per Jawad: make sharing app content outward SO easy that shared
artifacts drive installs — FOMO on top of the waitlist. This pass's themes:
consistency, QoL, performance, cleanup, shareability.

## Shipped

- **Profile share card** (this branch): 1080×1920 story-ready image —
  white ground, monochrome brand, ONE accent stolen from the avatar's
  prominent color (neutral gray fallback for monochrome/missing avatars),
  "@handle is On Board. Are you?", Pop Score total when nonzero (zero is
  an anti-flex and is suppressed), Host corner watermark per the
  CountdownCard recipe, "download now" CTA + domain. Replaces the bare-URL
  ShareLink whenever rendered; URL share is the fallback while rendering.

## Settled decisions

- **Post shares use the PostTone as the background** (Jawad, 2026-08-09).

## Post-share proposal (not yet built)

1. **The masonry card IS the share asset.** Full-bleed tone background,
   the post rendered as its real card composition (~85% width, real
   corner radius/rotation energy), reaction counts as stickers, campus
   name + wordmark, download CTA. The tone-colored card is the app's most
   recognizable artifact — don't invent a new composition.
2. **Ephemerality is the FOMO engine.** Every shared post card carries
   "gone Sunday night" / "clears in 2 days" — the content *disappears*,
   so the recipient must install before the clear to see the rest of the
   board. This is the differentiated hook no evergreen-content app can copy.
3. **Instagram Stories direct integration** (`instagram-stories://` +
   pasteboard payload: tone hexes as background gradient, card PNG as the
   sticker layer). One tap from the post → IG story composer with
   everything placed. Requires `LSApplicationQueriesSchemes` +=
   `instagram-stories`. ShareLink alone buries the story path in steps;
   this is the "make it easy" unlock.
4. **Open question for Jawad — authorship on shared cards.** The grid is
   quiet-authorship; a shared card leaving the campus gate arguably
   should be too. Options: (a) no handle on shared post cards (content +
   campus + timestamp only — preserves quietness externally, sidesteps
   consent questions about sharing someone's handle off-platform),
   (b) handle shown, (c) per-user "sharable" setting. Leaning (a).
5. **Share moments that convert** (from the polish research): right
   after posting your own post (motivation peak), "your post topped the
   board", and the parked weekly recap. Surface share CTAs there, not as
   ambient chrome.
6. **Attribution**: burn `?s=ig`-style ref params into shared URLs so
   installs can be attributed to share surfaces later (the web invite
   page already resolves codes; same pattern).

## QoL/consistency notes from this pass

- Tone picker now lives in the nav principal in BOTH composers (new post
  + edit) — one mental model.
- EDITING… indicator removed everywhere (chrome + morph already say it).
- Destructive actions audit: roles were largely correct (post/comment
  delete, block alert); the one fake (`.tint(.red)` atop an
  already-destructive Block menu item) removed. Red *informational* text
  (irreversibility warnings, error labels) is intentionally not
  role-based — roles are for actions.
