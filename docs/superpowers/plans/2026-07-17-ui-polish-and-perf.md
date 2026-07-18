# UI Polish + Perf Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six approved UX polish items (birthday wheel picker, textfield insets, post-form rhythm, shift-in edit transition, mock-mode social hiding, simulator UX hunt) followed by a perf pass.

**Architecture:** Pure view-layer changes. The one structural piece is a `matchedFieldText` helper in `BoardTextFieldStyle.swift` that registers the *text* frame (not the glass frame) with `matchedGeometryEffect`, producing the shift-in slide. No store, service, or model changes.

**Tech Stack:** SwiftUI, iOS 18+ (iOS 26 `glassEffect` behind availability), Swift Testing for regression suite.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-17-ui-polish-and-perf-design.md`.
- Build check: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"` — must print `** BUILD SUCCEEDED **`.
- Tests (regression gate, run in Task 6): `xcodebuild test -scheme "On Board" -destination "id=<UDID>" -parallel-testing-enabled NO` with a UDID from `xcrun simctl list devices available`.
- Visual work is verified on-simulator in mock mode (move `Secrets.xcconfig` aside; **always restore it**).
- This is styling work — TDD does not apply to pt-value changes; the verification cycle is build + on-sim eyeball + existing suite green. Do not invent view-snapshot infrastructure.
- Commit after each task. Do NOT commit the pre-existing uncommitted working tree (user hasn't approved that); stage only files this plan touches. Note: several files this plan touches are *already modified* in the tree (NewPostView, SignInView, PostDetailView+Views…). Staging the whole file therefore includes prior session work — acceptable ONLY for files the plan modifies, per user's "everything seems to work" confirmation; never `git add -A`.

---

### Task 1: Birthday step → wheel picker

**Files:**
- Rename: `On Board/Views/Components/BirthdayGraphicalPicker.swift` → `BirthdayWheelPicker.swift` (git mv; Xcode project uses folder-sync groups for this dir — verify with `grep BirthdayGraphical "On Board.xcodeproj/project.pbxproj"`; if referenced, update the pbxproj entry too)
- Modify: `On Board/Views/Onboarding/OnboardingBirthdayStepView.swift:32`

**Interfaces:**
- Produces: `struct BirthdayWheelPicker: View` with unchanged init `(date: Binding<Date?>, isEnabled: Bool = true, maximumDate: Date? = nil)`.

- [ ] **Step 1: Rename + restyle**

`git mv "On Board/Views/Components/BirthdayGraphicalPicker.swift" "On Board/Views/Components/BirthdayWheelPicker.swift"`

In the renamed file: type `BirthdayGraphicalPicker` → `BirthdayWheelPicker`, header comment updated, and the picker becomes:

```swift
DatePicker(
    "Birthday",
    selection: selection,
    in: ...(maximumDate ?? .now),
    displayedComponents: .date
)
.datePickerStyle(.wheel)
.labelsHidden()
.tint(.primary)
.frame(maxWidth: .infinity)
```

(`.frame(maxWidth: .infinity)` centers the wheel; without it the wheel hugs leading edge under an `alignment: .leading` VStack.)

Update doc comment: "Large ordinal-formatted date readout over a compact wheel picker".

- [ ] **Step 2: Update call site**

`OnboardingBirthdayStepView.swift:32`: `BirthdayGraphicalPicker(...)` → `BirthdayWheelPicker(...)`. Also update the `#Preview` in the renamed file.

- [ ] **Step 3: Build**

Run the build check command. Expected: `** BUILD SUCCEEDED **`. If pbxproj referenced the old filename, fix the reference.

- [ ] **Step 4: Commit**

```bash
git add "On Board/Views/Components/BirthdayWheelPicker.swift" "On Board/Views/Onboarding/OnboardingBirthdayStepView.swift" "On Board.xcodeproj/project.pbxproj"
git commit -m "Swap birthday onboarding calendar for a compact wheel picker"
```

---

### Task 2: Textfield inset bump

**Files:**
- Modify: `Styling/Styles/BoardTextFieldStyle.swift:82-89`

**Interfaces:**
- Produces: new inset values consumed by Task 3's `matchedFieldText` helper — standard (18, 16), title (12, 10), body (12, 10), username (10, 7).

- [ ] **Step 1: Bump insets**

```swift
private var inset: (h: CGFloat, v: CGFloat) {
    switch variant {
    case .standard: (18, 16)
    case .title: (12, 10)
    case .body: (12, 10)
    case .username: (10, 7)
    }
}
```

- [ ] **Step 2: Build + commit**

Build check → `** BUILD SUCCEEDED **`, then:

```bash
git add Styling/Styles/BoardTextFieldStyle.swift
git commit -m "Give glass textfields slightly more inner breathing room"
```

(Values may be re-tuned ±2 in Task 6 on-simulator; that re-tune amends into the Task 6 commit.)

---

### Task 3: Shift-in edit-mode transition

**Files:**
- Modify: `Styling/Styles/BoardTextFieldStyle.swift` (add helper at bottom)
- Modify: `On Board/Views/Profile/ProfileEditContent.swift:54,67,112`
- Modify: `On Board/Views/Post/PostDetailView+Views.swift:279,288`

**Interfaces:**
- Consumes: `GlassFieldChrome`'s inset values (Task 2). To avoid duplication, hoist the inset switch to `BoardTextFieldStyle.Variant` so both the chrome and the helper read one source of truth.
- Produces: `View.matchedFieldText(id:in:variant:anchor:)` — drop-in replacement for `matchedGeometryEffect` on `.boardTitle`/`.boardBody`/`.boardUsername` fields.

**Why this works:** today the matched pair is read-`Text`-frame ↔ glass-frame; the edit text sits one inset deeper than the glass edge, so the morph reads as a fade-jump. Applying `.padding(-inset)` to the *styled* field yields a frame exactly congruent with the inner text (glass overflows symmetrically); registering *that* frame with `matchedGeometryEffect` and restoring the footprint with `.padding(+inset)` outside makes the morph interpolate text-position → text-position: the text visibly slides inward by one inset while the glass fades in around it. Runs inside the existing `withAnimation(.smooth(0.3))` transaction — no two-phase settle, no onAppear animation.

- [ ] **Step 1: Hoist insets onto Variant + add helper** (in `BoardTextFieldStyle.swift`)

```swift
extension BoardTextFieldStyle.Variant {
    /// Inner glass padding. Single source of truth — GlassFieldChrome pads by
    /// it, matchedFieldText(id:in:variant:) negates by it to register the text
    /// frame instead of the glass frame.
    var inset: (h: CGFloat, v: CGFloat) {
        switch self {
        case .standard: (18, 16)
        case .title: (12, 10)
        case .body: (12, 10)
        case .username: (10, 7)
        }
    }
}

extension View {
    /// matchedGeometryEffect for a glass field that registers the *text*
    /// frame, not the glass frame. Paired with a plain Text on the read side,
    /// the edit-mode morph slides the text inward to its inset position as the
    /// chrome appears, instead of crossfading two offset copies.
    func matchedFieldText(
        id: some Hashable,
        in namespace: Namespace.ID,
        variant: BoardTextFieldStyle.Variant,
        anchor: UnitPoint = .leading
    ) -> some View {
        let inset = variant.inset
        return self
            .padding(.horizontal, -inset.h)
            .padding(.vertical, -inset.v)
            .matchedGeometryEffect(id: id, in: namespace, anchor: anchor)
            .padding(.horizontal, inset.h)
            .padding(.vertical, inset.v)
    }
}
```

In `GlassFieldChrome`, replace the private `inset` computed property with `variant.inset` (delete lines 82-89, use `variant.inset.h` / `variant.inset.v` at the padding call sites, or bind `let inset = variant.inset` in `body`).

- [ ] **Step 2: Swap the five edit-side call sites**

`ProfileEditContent.swift`:
- line 54: `.matchedGeometryEffect(id: ProfileGeometryID.displayName, in: namespace, anchor: .leading)` → `.matchedFieldText(id: ProfileGeometryID.displayName, in: namespace, variant: .title)`
- line 67 (username): → `.matchedFieldText(id: ProfileGeometryID.username, in: namespace, variant: .username)`
- line 112 (bio): → `.matchedFieldText(id: ProfileGeometryID.bio, in: namespace, variant: .body)`

`PostDetailView+Views.swift`:
- line 279 (postTitle): → `.matchedFieldText(id: "postTitle", in: postNamespace, variant: .title)`
- line 288 (postDescription): → `.matchedFieldText(id: "postDescription", in: postNamespace, variant: .body)`

Read sides unchanged.

- [ ] **Step 3: Build + commit**

Build check → `** BUILD SUCCEEDED **`.

```bash
git add Styling/Styles/BoardTextFieldStyle.swift "On Board/Views/Profile/ProfileEditContent.swift" "On Board/Views/Post/PostDetailView+Views.swift"
git commit -m "Slide field text inward on edit-mode entry instead of crossfading"
```

On-sim verification happens in Task 6 (profile edit toggle + post edit toggle, both directions, plus interactive-swipe pop while editing).

---

### Task 4: Post-form vertical rhythm

**Files:**
- Modify: `On Board/Views/Feed/NewPostView.swift:55`
- Modify: `On Board/Views/Post/PostDetailView+Views.swift:81`

- [ ] **Step 1: Tighten spacings**

- `NewPostView.swift:55`: `VStack(alignment: .leading, spacing: 20)` → `spacing: 16`, and update the comment above it (it references 20pt).
- `PostDetailView+Views.swift:81`: `VStack(alignment: .leading, spacing: 20)` → `spacing: 16`. NOTE: this stack is shared by read AND edit mode of post detail — eyeball both in Task 6; if read mode suffers, revert this line and instead tighten only edit mode via a `.padding(.top, -4)` on the second field. Also update the "outer VStack's 20pt spacing" comment at line 271.

- [ ] **Step 2: Build + commit**

Build check → `** BUILD SUCCEEDED **`.

```bash
git add "On Board/Views/Feed/NewPostView.swift" "On Board/Views/Post/PostDetailView+Views.swift"
git commit -m "Tighten vertical rhythm in post composer and editor"
```

Final values tuned in Task 6.

---

### Task 5: Hide social sign-in in mock mode

**Files:**
- Modify: `On Board/Views/Auth/SignInView.swift:105` (socialSection call site)
- Modify: `On Board/Views/Settings/AccountSecuritySettingsView.swift:161-176` (thirdPartySection)

- [ ] **Step 1: Gate SignInView**

At `SignInView.swift:105`, wrap the socialSection (the existing `usesLiveBackend` property already reads `AppConfiguration.current.isSupabaseConfigured`):

```swift
if usesLiveBackend {
    socialSection
}
```

- [ ] **Step 2: Gate settings section**

In `AccountSecuritySettingsView.swift`, wrap the whole `thirdPartySection` body so section, rows, and footer all disappear together:

```swift
@ViewBuilder
private var thirdPartySection: some View {
    if AppConfiguration.current.isSupabaseConfigured {
        Section {
            if let session = auth.session {
                appleMethodRow(session: session)
                googleMethodRow(session: session)
            }
        } header: {
            Text("Third-Party")
                .fontStyle(.subheadline)
        } footer: {
            Text("To remove Apple or Google, add a phone number, email, or another linked account first.")
                .fontStyle(.footnote)
        }
    }
}
```

(This supersedes googleMethodRow's mock-mode affordance `|| !AppConfiguration.current.isSupabaseConfigured` — leave that expression in place; it's simply unreachable in mock now.)

- [ ] **Step 3: Build + commit**

Build check → `** BUILD SUCCEEDED **`.

```bash
git add "On Board/Views/Auth/SignInView.swift" "On Board/Views/Settings/AccountSecuritySettingsView.swift"
git commit -m "Hide social sign-in UI entirely in mock (no-Supabase) builds"
```

---

### Task 6: Simulator verification + UX hunt

**Files:** none planned — whatever small polish emerges. Structural ideas go to the report, not code.

- [ ] **Step 1: Enter mock mode (guarded)**

```bash
mv Secrets.xcconfig /private/tmp/claude-501/-Users-jawadkhadra-On-Board-onboard-ios/36630942-6822-43e4-bb93-92a40aa9f5e0/scratchpad/Secrets.xcconfig.bak
```

From this point, EVERY exit path restores it (`mv` back) — including failures.

- [ ] **Step 2: Boot sim, build, install, launch**

```bash
xcrun simctl list devices available   # pick an iPhone UDID
xcodebuild -scheme "On Board" -destination "id=<UDID>" build
xcrun simctl boot <UDID> 2>/dev/null; open -a Simulator
# find the built .app path via -showBuildSettings TARGET_BUILD_DIR/WRAPPER_NAME
xcrun simctl install <UDID> "<path>/On Board.app"
xcrun simctl launch <UDID> <bundle-id>   # bundle id from build settings PRODUCT_BUNDLE_IDENTIFIER
```

To skip sign-in when needed, relaunch with the documented seed: `xcrun simctl launch <UDID> <bundle-id> -mock.auth.session "<hex>"` (per CLAUDE.md, SampleProfileID.maya; hex is built from JSON AuthSession — see repo docs/tests for the exact shape used by MockAuthService).

- [ ] **Step 3: Walk + screenshot every flow**

`xcrun simctl io <UDID> screenshot <scratchpad>/shot-<name>.png` at each stop: sign-in (no social buttons), onboarding birthday (wheel), remaining onboarding steps, feed, new post composer, post detail read, post edit (shift-in!), comments, profile read, profile edit (shift-in!), settings → account security (no Third-Party section). For the two shift-in transitions, capture video: `xcrun simctl io <UDID> recordVideo --codec h264 <scratchpad>/edit-morph.mov` while toggling edit mode (frame-decode via AVAssetReader if inspection needed, per CLAUDE.md note that XCUITest screenshots land post-animation).

- [ ] **Step 4: Tune by eye**

Adjust Task 2 inset values / Task 4 spacings if they read wrong on-device; small polish fixes (spacing, timing, copy) applied directly. Each tweak: edit → rebuild → reinstall → re-screenshot. Commit tuning as one commit: `git commit -m "Tune polish values from on-simulator review"`.

- [ ] **Step 5: Regression tests**

```bash
xcodebuild test -scheme "On Board" -destination "id=<UDID>" -parallel-testing-enabled NO
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Restore Secrets.xcconfig**

```bash
mv <scratchpad>/Secrets.xcconfig.bak Secrets.xcconfig
git status --short   # confirm no stray changes
```

---

### Task 7: Perf pass

**Files:** read-first sweep; candidates below are hypotheses to verify, not conclusions.

- [ ] **Step 1: Static sweep** — grep/read for the spec's five categories:
  - Formatters/`Calendar` built per-render in `body` paths (e.g. `BirthdayWheelPicker.ordinalFormatted` builds none — good; check `PostCard`, `CommentRow`, `ProfileMetaRow` uses cached `static` formatters — pattern already present at `ProfileReadContent.swift:177`).
  - Always-on animations: `NewPostView`'s `AnimatedStripesView(isActive: true)` + `repeatForever` pulse; check `AnimatedStripesView` uses `TimelineView`/`Canvas` and whether it pauses off-screen.
  - The 60s `Task.sleep` polling loop in `NewPostView` (cheap, but verify it cancels on dismiss — `.task` handles this).
  - Feed masonry: check `BoardFeedView` for per-render sorting/partitioning of posts that could be cached on the store.
  - Image handling: `ImageUploader` already encodes off-main (comment at NewPostView:277); check `AvatarView`/post images for missing `.resizable` downsampling or repeated `UIImage(data:)` decodes in `body` (ProfileEditContent:151 decodes `UIImage(data:)` every render — candidate: cache decoded image in `ProfileDraft`).
- [ ] **Step 2: Apply safe wins** — no-behavior-change fixes (hoist per-render work, pause off-screen animations, cache decodes). One commit per logical fix, build check each.
- [ ] **Step 3: Instruments-style smoke** — relaunch on sim, scroll feed hard, open/close composer and edit modes; watch for hitches. (No Instruments automation — eyeball + `simctl` video review.)
- [ ] **Step 4: Propose risky ones** — anything touching store semantics/caching goes in the final report only.

---

### Task 8: Final report

- [ ] Build + full tests green (evidence in hand), `Secrets.xcconfig` restored, screenshots collected.
- [ ] Report: what changed (by commit), before/after screenshots via SendUserFile, UX proposals list, perf findings (applied vs proposed), anything skipped and why.
