# UI Polish + Perf Pass — Design

**Date:** 2026-07-17
**Status:** Approved (verbally, pre-gym) — implement under "polish freely, report big ideas" latitude.

## Goal

A focused polish pass over recently-shipped UI, followed by a performance pass.
Six UX items, then perf. Small/low-risk changes land directly; structural ideas
become written proposals.

## 1. Birthday step → wheel picker

`BirthdayGraphicalPicker` currently shows a heavy always-visible `.graphical`
calendar grid. Replace with `.wheel`:

- Rename component to `BirthdayWheelPicker` (file + type + call site in
  `OnboardingBirthdayStepView`).
- Keep the ordinal headline ("August 20th, 2006") with `.contentTransition(.numericText())`.
- Keep `labelsHidden`, `.tint(.primary)`, max-date clamp (16+ only), and the
  nil-date → resolvedDate binding behavior exactly as-is.
- Caption, "show month/day" toggle, Continue button unchanged.

**Success:** birthday step reads as headline + one compact control, no calendar grid.

## 2. Textfield inner padding bump

All four `inset` variants in `BoardTextFieldStyle.GlassFieldChrome` get ~+2pt:

| Variant | Old (h, v) | New (h, v) |
|---|---|---|
| standard | 16, 14 | 18, 16 |
| title | 10, 8 | 12, 10 |
| body | 10, 8 | 12, 10 |
| username | 8, 5 | 10, 7 |

Call sites that negate these insets (the WYSIWYG padding sandwich) must be
found (`grep` for negative paddings near `.boardTitle`/`.boardBody`/`.boardUsername`)
and updated in the same commit. Final values may be tuned ±2pt on-simulator.

## 3. Tighter vertical rhythm in post forms

`NewPostView`'s main `VStack(spacing: 20)` → ~14–16; matching stacks in the
post-edit path (`PostDetailView+Views`) and `ProfileEditContent` get the same
treatment. Values are tuned by eye on the simulator, not committed blind.

## 4. Shift-in edit-mode transition

Entering edit mode, field text currently stays put while glass chrome fades in.
New behavior: the text *slides inward* to its inset position inside the glass
(and back out on exit) as one animation — read → edit reads as the same text
gliding into a field.

- Mechanism decided on-device: animated inset padding vs `matchedGeometryEffect`.
  Whichever avoids two-phase layout settle (a previously-fixed bug — see
  BoardTextFieldStyle comments) wins.
- Reduce Motion: keep today's fade, no movement.

## 5. Hide social sign-in in mock mode

Gate on `!AppConfiguration.isSupabaseConfigured`:

- `AccountSecuritySettingsView`: hide Apple/Google link rows and the related
  footer text.
- `SignInView`: hide Apple/Google buttons; email flow only.
- Live builds unchanged. Mock services keep their social code paths (unit tests
  still exercise them); this is view-layer hiding only.

## 6. Simulator UX hunt

- Temporarily move `Secrets.xcconfig` aside to force mock mode; **restore it
  when done** (guarded step — restore even on failure).
- Walk: sign-in → onboarding (all steps) → feed → new post → post detail →
  comments → profile → profile edit → settings.
- Screenshot each screen. Small polish (spacing, animation timing, copy) is
  fixed directly. Structural ideas go in the final report as proposals.

## 7. Perf pass (after UX work)

Hunt for and apply safe wins; propose risky ones:

- Expensive `body` recomputation (formatters constructed per-render, heavy
  computed properties in `@Observable` dependency paths).
- Redundant store work (repeated sorts/filters per render vs cached).
- Animation/timeline cost (always-on `TimelineView`/`Canvas`, off-screen
  animations that keep running).
- Image handling (full-size avatar decodes, missing downsampling).
- List/scroll performance in the masonry feed.

Safe = no behavior change, verifiable by build+tests+on-sim smoke. Anything
touching store semantics or caching is proposal-only.

## Verification

- `xcodebuild` build green; full test suite green (`-parallel-testing-enabled NO`).
- On-simulator walkthrough of every touched screen in mock mode.
- Screenshots before/after for visual changes.

## Out of scope

- Committing the pre-existing uncommitted work (separate, awaiting explicit go).
- Backend/Supabase changes.
- New features.
