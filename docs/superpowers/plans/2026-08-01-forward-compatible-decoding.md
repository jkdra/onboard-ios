# Forward-Compatible Wire Decoding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every enum that crosses the Supabase wire decode unknown values gracefully instead of throwing, so a value added in a future build cannot break clients that haven't updated.

**Architecture:** Five `String`-backed enums currently use fail-closed decoding. Because each is decoded inside an array (`[RemotePostRow]`, `[UserReactionRow]`, `[UserCommentVoteRow]`), one unknown value fails the *entire* response — not one row. Each gets a fallback policy chosen for its semantics: tones map deterministically to a known tone, reactions and votes are dropped, board statuses degrade to read-only, and an unrecognized onboarding step routes to a "please update" screen because no local behavior is correct.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test`/`#expect`), supabase-swift.

## Global Constraints

- Minimum deployment target is iOS 18. iOS 26 APIs require `#available(iOS 26.0, *)` guards.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- **Never write snake_case `CodingKeys`** on a type crossing PostgREST. `BoardJSON` applies `.convertToSnakeCase`/`.convertFromSnakeCase`; explicit snake_case keys make encoding still work while decoding always throws `keyNotFound`.
- **Never use `String.hashValue`** for anything persisted, rendered, or bucketed. Swift seeds it per process, so the same input produces a different result after every app restart.
- This module defaults to MainActor isolation. Decoding runs off-main, so `init(from:)` and any static helper it calls must be marked `nonisolated`.
- Build check: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
- Test run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
- The Read tool requires **literal spaces** in paths (`On Board/...`), never backslash-escaped.

## File Structure

| File | Responsibility |
|---|---|
| `On Board/Extensions/StableHash.swift` | **Create.** Process-stable FNV-1a hash. Used here by `PostTone`; reused later by feature-flag bucketing. |
| `On Board/Models/PostTone.swift` | **Modify.** Add lenient `init(from:)` + `stableFallback(for:)`. |
| `On Board/Models/BoardWeek.swift` | **Modify.** Line 72 — decode `Status` leniently. |
| `On Board/Supabase/SupabaseBoardService.swift` | **Modify.** Lines 100–108 — `UserReactionRow.type` and `UserCommentVoteRow.vote` carry raw `String`. |
| `On Board/Supabase/SupabaseBoardService+Posts.swift` | **Modify.** Line 56 — map + drop unknown reactions. |
| `On Board/Supabase/SupabaseBoardService+Comments.swift` | **Modify.** Line 26 — map + drop unknown votes. |
| `On Board/Models/OnboardingStep.swift` | **Modify.** Add `.unrecognized`, excluded from `allCases`. |
| `On Board/Views/Onboarding/OnboardingUpdateRequiredView.swift` | **Create.** Terminal screen for `.unrecognized`. |
| `On Board/Onboarding/OnboardingCoordinator.swift` | **Modify.** Handle `.unrecognized` in `effectiveStep` and the destination switch. |
| `On BoardTests/WireEnumDecodingTests.swift` | **Create.** All tests for this plan. |

---

### Task 1: Stable hash helper and lenient `PostTone`

**Files:**
- Create: `On Board/Extensions/StableHash.swift`
- Modify: `On Board/Models/PostTone.swift`
- Test: `On BoardTests/WireEnumDecodingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `StableHash.fnv1a(_ string: String) -> UInt64` (nonisolated, static). `PostTone.stableFallback(for raw: String) -> PostTone` (nonisolated, static).

- [ ] **Step 1: Write the failing test**

Create `On BoardTests/WireEnumDecodingTests.swift`:

```swift
//
//  WireEnumDecodingTests.swift
//  On BoardTests
//
//  Pins forward compatibility for every enum that crosses the Supabase wire.
//  Each of these enums is decoded inside an array, so a throw on one unknown
//  value fails the whole response — see the `arrayDecodeSurvives...` cases.
//

import Foundation
import Testing
@testable import On_Board

struct PostToneDecodingTests {
    @Test func decodesKnownTone() throws {
        let tone = try JSONDecoder().decode(PostTone.self, from: Data(#""mint""#.utf8))
        #expect(tone == .mint)
    }

    @Test func mapsUnknownToneToAKnownToneInsteadOfThrowing() throws {
        let tone = try JSONDecoder().decode(PostTone.self, from: Data(#""crimson""#.utf8))
        #expect(PostTone.allCases.contains(tone))
    }

    @Test func unknownToneMapsDeterministically() {
        #expect(PostTone.stableFallback(for: "crimson") == PostTone.stableFallback(for: "crimson"))
    }

    @Test func differentUnknownTonesDoNotAllCollapseToOneColor() {
        let raws = ["crimson", "amber", "violet", "cyan", "magenta", "olive", "slate", "rose"]
        let mapped = Set(raws.map { PostTone.stableFallback(for: $0) })
        #expect(mapped.count > 1)
    }

    @Test func arrayDecodeSurvivesOneUnknownTone() throws {
        let json = Data(#"["blue","crimson","mint"]"#.utf8)
        let tones = try JSONDecoder().decode([PostTone].self, from: json)
        #expect(tones.count == 3)
        #expect(tones[0] == .blue)
        #expect(tones[2] == .mint)
    }
}

struct StableHashTests {
    @Test func isDeterministicForTheSameInput() {
        #expect(StableHash.fnv1a("onboard") == StableHash.fnv1a("onboard"))
    }

    @Test func differsForDifferentInputs() {
        #expect(StableHash.fnv1a("onboard") != StableHash.fnv1a("onboarding"))
    }

    @Test func matchesKnownFNV1aVector() {
        // Canonical FNV-1a 64-bit test vector for "a".
        #expect(StableHash.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/StableHashTests"`

Expected: FAIL to compile — `cannot find 'StableHash' in scope`.

- [ ] **Step 3: Create the stable hash helper**

Create `On Board/Extensions/StableHash.swift`:

```swift
//
//  StableHash.swift
//  On Board
//
//  A process-stable hash.
//
//  `String.hashValue` is seeded per process, so the same input produces a
//  different value after every app restart. That makes it unusable for anything
//  the user can perceive across launches — a color derived from it would flicker,
//  and a feature-flag bucket derived from it would move a user in and out of a
//  rollout on every cold start. Use this instead for any of those.
//

import Foundation

enum StableHash {
    /// FNV-1a, 64-bit. Chosen for being tiny, dependency-free, and stable
    /// forever — not for cryptographic strength. Never use for security.
    nonisolated static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
```

- [ ] **Step 4: Add the lenient decoder to `PostTone`**

In `On Board/Models/PostTone.swift`, add these members inside the `enum PostTone` body, immediately after `static func random()`:

```swift
    /// Unknown wire values map to a known tone instead of throwing.
    ///
    /// `fetch_posts_for_week` decodes `[RemotePostRow]`, so a throw here fails
    /// the *entire* feed response, not one card — a tone added in a future build
    /// would blank the board for every client that hadn't updated, for the whole
    /// week, with no way to recover the content once the board clears.
    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PostTone(rawValue: raw) ?? PostTone.stableFallback(for: raw)
    }

    /// Deterministic so an unknown tone renders the same color on every launch
    /// and every device, and so a board full of unknown tones stays varied
    /// instead of collapsing to a single color.
    ///
    /// Must use `StableHash`, not `hashValue` — see that type's doc comment.
    nonisolated static func stableFallback(for raw: String) -> PostTone {
        let index = Int(StableHash.fnv1a(raw) % UInt64(allCases.count))
        return allCases[index]
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/StableHashTests" -only-testing "On BoardTests/PostToneDecodingTests"`

Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Extensions/StableHash.swift" "On Board/Models/PostTone.swift" "On BoardTests/WireEnumDecodingTests.swift"
git commit -m "Decode unknown post tones instead of failing the whole feed"
```

---

### Task 2: Lenient `BoardWeek.Status`

**Files:**
- Modify: `On Board/Models/BoardWeek.swift:72`
- Test: `On BoardTests/WireEnumDecodingTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: no new public API. `BoardWeek.Status` decoding becomes total.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/WireEnumDecodingTests.swift`:

```swift
struct BoardWeekStatusDecodingTests {
    /// Minimal `BoardWeek` JSON with a swappable status.
    private func weekJSON(status: String) -> Data {
        Data("""
        {
            "id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01",
            "board_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02",
            "starts_at": "2026-08-03T00:00:00Z",
            "ends_at": "2026-08-10T00:00:00Z",
            "status": "\(status)",
            "post_count": 4
        }
        """.utf8)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func decodesKnownStatus() throws {
        let week = try decoder.decode(BoardWeek.self, from: weekJSON(status: "archived"))
        #expect(week.status == .archived)
    }

    @Test func unknownStatusDegradesToReadOnlyInsteadOfThrowing() throws {
        let week = try decoder.decode(BoardWeek.self, from: weekJSON(status: "frozen"))
        #expect(week.status == .archived)
        #expect(week.isReadOnly)
    }

    @Test func arrayDecodeSurvivesOneUnknownStatus() throws {
        let json = Data("[\(String(decoding: weekJSON(status: "active"), as: UTF8.self)),\(String(decoding: weekJSON(status: "frozen"), as: UTF8.self))]".utf8)
        let weeks = try decoder.decode([BoardWeek].self, from: json)
        #expect(weeks.count == 2)
        #expect(weeks[0].status == .active)
        #expect(weeks[1].status == .archived)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/BoardWeekStatusDecodingTests"`

Expected: FAIL — `unknownStatusDegradesToReadOnlyInsteadOfThrowing` and `arrayDecodeSurvivesOneUnknownStatus` throw `DecodingError.dataCorrupted`.

- [ ] **Step 3: Make the status decode total**

In `On Board/Models/BoardWeek.swift`, replace line 72:

```swift
        status = try container.decode(Status.self, forKey: .status)
```

with:

```swift
        status = Self.decodeStatus(from: container)
```

Then add this static helper inside `struct BoardWeek`, immediately after `init(from:)`:

```swift
    /// Unknown statuses decode as `.archived` rather than throwing.
    ///
    /// A status added server-side would otherwise fail the whole
    /// `list_board_weeks` response and leave the app with no board at all.
    /// `.archived` (read-only) is the safer of the two landing spots: statuses
    /// get added to express *new restrictions* (frozen, locked, moderated), not
    /// new permissions, so read-only is the more likely-correct reading. It also
    /// never costs the user written work — the alternative, `.active`, would let
    /// them compose a post the server then rejects.
    ///
    /// The real fix for an old client seeing an unknown status is to prompt it to
    /// update; that arrives with the version gate. This keeps it alive until then.
    nonisolated private static func decodeStatus(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Status {
        guard let raw = try? container.decode(String.self, forKey: .status) else {
            return .archived
        }
        return Status(rawValue: raw) ?? .archived
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/BoardWeekStatusDecodingTests"`

Expected: PASS, 3 tests.

- [ ] **Step 5: Run the existing `BoardWeekDecodingTests` to check for regressions**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/BoardWeekDecodingTests"`

Expected: PASS. `missingBoardIdFailsInsteadOfSubstitutingDevBoard` must still fail-closed — this change must not have made `boardId` lenient.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Models/BoardWeek.swift" "On BoardTests/WireEnumDecodingTests.swift"
git commit -m "Degrade unknown board-week statuses to read-only instead of throwing"
```

---

### Task 3: Drop unknown reactions instead of failing the feed

**Files:**
- Modify: `On Board/Supabase/SupabaseBoardService.swift:100-103`
- Modify: `On Board/Supabase/SupabaseBoardService+Posts.swift:56`
- Test: `On BoardTests/WireEnumDecodingTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces: `SupabaseBoardService.UserReactionRow.type` changes type from `Reaction` to `String`. Any future call site must map with `Reaction(rawValue:)` and drop `nil`.

**Why drop rather than map:** an unknown reaction mapped onto a known one would silently inflate that reaction's count. Dropping loses one user's reaction display until they update; mapping corrupts data for everyone.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/WireEnumDecodingTests.swift`:

```swift
struct ReactionRowDecodingTests {
    @Test func arrayDecodeSurvivesAnUnknownReactionType() throws {
        let json = Data("""
        [
            {"post_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01", "type": "like"},
            {"post_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02", "type": "sparkle"}
        ]
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([SupabaseBoardService.UserReactionRow].self, from: json)

        #expect(rows.count == 2)

        // The unknown type is dropped at mapping time, not decode time.
        let mapped = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            Reaction(rawValue: row.type).map { (row.postId, $0) }
        })
        #expect(mapped.count == 1)
        #expect(mapped.values.first == .like)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/ReactionRowDecodingTests"`

Expected: FAIL — decoding throws `DecodingError.dataCorrupted` on `"sparkle"`.

- [ ] **Step 3: Change the row to carry the raw value**

In `On Board/Supabase/SupabaseBoardService.swift`, replace lines 100–103:

```swift
    struct UserReactionRow: Decodable, Sendable {
        let postId: UUID
        let type: Reaction
    }
```

with:

```swift
    struct UserReactionRow: Decodable, Sendable {
        let postId: UUID
        /// Raw wire value, deliberately **not** `Reaction`.
        ///
        /// `fetch_my_reactions_for_week` decodes `[UserReactionRow]`, so a
        /// reaction type added in a future build would fail this whole array —
        /// and with it the feed. Callers map via `Reaction(rawValue:)` and drop
        /// `nil`: mapping an unknown reaction onto a known one would silently
        /// inflate that reaction's count.
        let type: String
    }
```

- [ ] **Step 4: Update the call site to map and drop**

In `On Board/Supabase/SupabaseBoardService+Posts.swift`, replace line 56:

```swift
            userReactions: Dictionary(uniqueKeysWithValues: reactionRows.map { ($0.postId, $0.type) })
```

with:

```swift
            userReactions: Dictionary(
                uniqueKeysWithValues: reactionRows.compactMap { row in
                    Reaction(rawValue: row.type).map { (row.postId, $0) }
                }
            )
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/ReactionRowDecodingTests"`

Expected: PASS, 1 test.

- [ ] **Step 6: Verify the whole project still builds**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`. If any other call site referenced `UserReactionRow.type` as a `Reaction`, it surfaces here — apply the same `compactMap` treatment.

- [ ] **Step 7: Commit**

```bash
git add "On Board/Supabase/SupabaseBoardService.swift" "On Board/Supabase/SupabaseBoardService+Posts.swift" "On BoardTests/WireEnumDecodingTests.swift"
git commit -m "Drop unknown reaction types instead of failing the feed decode"
```

---

### Task 4: Drop unknown comment votes

**Files:**
- Modify: `On Board/Supabase/SupabaseBoardService.swift:105-108`
- Modify: `On Board/Supabase/SupabaseBoardService+Comments.swift:26`
- Test: `On BoardTests/WireEnumDecodingTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–3.
- Produces: `SupabaseBoardService.UserCommentVoteRow.vote` changes type from `CommentVote` to `String`.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/WireEnumDecodingTests.swift`:

```swift
struct CommentVoteRowDecodingTests {
    @Test func arrayDecodeSurvivesAnUnknownVote() throws {
        let json = Data("""
        [
            {"comment_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E01", "vote": "like"},
            {"comment_id": "6BFB4A31-3D2E-4E0E-9B39-6E0B0C9E9E02", "vote": "superlike"}
        ]
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([SupabaseBoardService.UserCommentVoteRow].self, from: json)

        #expect(rows.count == 2)

        let mapped = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            CommentVote(rawValue: row.vote).map { (row.commentId, $0) }
        })
        #expect(mapped.count == 1)
        #expect(mapped.values.first == .like)
    }
}
```

`CommentVote`'s cases are `like` and `dislike` (`On Board/Models/Comment.swift:83`),
so `"superlike"` is the unknown value.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/CommentVoteRowDecodingTests"`

Expected: FAIL — decoding throws on `"superup"`.

- [ ] **Step 3: Change the row to carry the raw value**

In `On Board/Supabase/SupabaseBoardService.swift`, replace lines 105–108:

```swift
    struct UserCommentVoteRow: Decodable, Sendable {
        let commentId: UUID
        let vote: CommentVote
    }
```

with:

```swift
    struct UserCommentVoteRow: Decodable, Sendable {
        let commentId: UUID
        /// Raw wire value, deliberately **not** `CommentVote` — same reasoning as
        /// `UserReactionRow.type`. Callers map via `CommentVote(rawValue:)` and
        /// drop `nil`, which reads as "no vote" rather than a wrong vote.
        let vote: String
    }
```

- [ ] **Step 4: Update the call site to map and drop**

In `On Board/Supabase/SupabaseBoardService+Comments.swift`, replace line 26:

```swift
            userVotes: Dictionary(uniqueKeysWithValues: voteRows.map { ($0.commentId, $0.vote) })
```

with:

```swift
            userVotes: Dictionary(
                uniqueKeysWithValues: voteRows.compactMap { row in
                    CommentVote(rawValue: row.vote).map { (row.commentId, $0) }
                }
            )
```

- [ ] **Step 5: Run the test and the build**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/CommentVoteRowDecodingTests"`

Expected: PASS, 1 test.

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Supabase/SupabaseBoardService.swift" "On Board/Supabase/SupabaseBoardService+Comments.swift" "On BoardTests/WireEnumDecodingTests.swift"
git commit -m "Drop unknown comment votes instead of failing the thread decode"
```

---

### Task 5: `OnboardingStep.unrecognized` and the update-required screen

**Files:**
- Modify: `On Board/Models/OnboardingStep.swift`
- Create: `On Board/Views/Onboarding/OnboardingUpdateRequiredView.swift`
- Modify: `On Board/Onboarding/OnboardingCoordinator.swift:41-61` and its `navigationDestination` switch
- Test: `On BoardTests/WireEnumDecodingTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–4.
- Produces: `OnboardingStep.unrecognized` case. `OnboardingStep.allCases` **excludes** it (manual `allCases`), so `OnboardingCoordinator.rank(_:)` and `OnboardingProgressBar` indices are unchanged.

**Why this one is different:** every other enum here has a safe local fallback. This one does not. Mapping an unknown step to `.complete` would admit a user who never finished onboarding; mapping to any concrete step could trap them in a loop they cannot exit. The only correct behavior is to stop and tell them to update.

- [ ] **Step 1: Write the failing test**

Append to `On BoardTests/WireEnumDecodingTests.swift`:

```swift
struct OnboardingStepDecodingTests {
    @Test func decodesKnownStep() throws {
        let step = try JSONDecoder().decode(OnboardingStep.self, from: Data(#""school_verify""#.utf8))
        #expect(step == .schoolVerify)
    }

    @Test func unknownStepDecodesAsUnrecognizedInsteadOfThrowing() throws {
        let step = try JSONDecoder().decode(OnboardingStep.self, from: Data(#""alumni_verify""#.utf8))
        #expect(step == .unrecognized)
    }

    /// `.unrecognized` must never appear in `allCases`: `OnboardingCoordinator.rank(_:)`
    /// uses `allCases.firstIndex(of:)` for step ordering, and `OnboardingProgressBar`
    /// takes a step index. A synthesized `allCases` containing the sentinel would
    /// silently shift that arithmetic.
    @Test func unrecognizedIsExcludedFromAllCases() {
        #expect(!OnboardingStep.allCases.contains(.unrecognized))
        #expect(OnboardingStep.allCases.count == 8)
    }

    @Test func knownStepsStillRoundTrip() throws {
        for step in OnboardingStep.allCases {
            let data = try JSONEncoder().encode(step)
            let decoded = try JSONDecoder().decode(OnboardingStep.self, from: data)
            #expect(decoded == step)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/OnboardingStepDecodingTests"`

Expected: FAIL to compile — `type 'OnboardingStep' has no member 'unrecognized'`.

- [ ] **Step 3: Add the sentinel case**

In `On Board/Models/OnboardingStep.swift`, add the case and a manual `allCases` and decoder. The full file becomes:

```swift
//
//  OnboardingStep.swift
//  On Board
//

import Foundation

enum OnboardingStep: String, Codable, Sendable, CaseIterable, Hashable {
    case birthday
    case username
    case profile
    /// Client-only step — never persisted server-side (no backing DB column/enum
    /// value). Completion is tracked locally via `@AppStorage`, since the content
    /// preference it sets (`profanityEnabled`) is itself a local, per-device
    /// setting, not account data. See `OnboardingCoordinator.effectiveStep`.
    case contentPreferences = "content_preferences"
    case schoolVerify = "school_verify"
    /// Client-only step — never persisted server-side (no backing DB enum value).
    /// Inserted after school verification when `expected_graduation` is still
    /// null; the persisted field itself is the completion signal (unlike
    /// contentPreferences, which uses a local flag). See
    /// `OnboardingCoordinator.effectiveStep`.
    case graduation
    case waitlist
    case complete

    /// A step this build doesn't know about — a value added to the
    /// `onboarding_step` Postgres enum after this version shipped.
    ///
    /// Every other wire enum in the app degrades to a usable local value. This
    /// one deliberately does not: mapping an unknown step to `.complete` would
    /// admit a user who never finished onboarding, and mapping it to any concrete
    /// step could trap them in a loop with no exit. Stopping and asking them to
    /// update is the only correct behavior, so this routes to
    /// `OnboardingUpdateRequiredView`.
    case unrecognized = "__unrecognized__"

    /// Deliberately excludes `.unrecognized`. `OnboardingCoordinator.rank(_:)`
    /// uses `allCases.firstIndex(of:)` for step ordering and `OnboardingProgressBar`
    /// takes a step index — a sentinel in this list would shift both.
    static var allCases: [OnboardingStep] {
        [.birthday, .username, .profile, .contentPreferences,
         .schoolVerify, .graduation, .waitlist, .complete]
    }

    nonisolated init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OnboardingStep(rawValue: raw) ?? .unrecognized
    }
}
```

- [ ] **Step 4: Run the decoding tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO -only-testing "On BoardTests/OnboardingStepDecodingTests"`

Expected: PASS, 4 tests.

- [ ] **Step 5: Create the update-required screen**

Create `On Board/Views/Onboarding/OnboardingUpdateRequiredView.swift`:

```swift
//
//  OnboardingUpdateRequiredView.swift
//  On Board
//
//  Terminal screen for `OnboardingStep.unrecognized` — the server asked this
//  build to show an onboarding step it has never heard of, which means the
//  client is older than the account's onboarding flow. There is no correct
//  local behavior, so this stops and points at the App Store.
//
//  Deliberately has no back affordance and no way to skip: any escape hatch
//  would drop the user into a flow that cannot complete.
//

import SwiftUI

struct OnboardingUpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Time for an update")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("This version of On Board is too old to finish setting up your account. Update to the latest version to continue.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                openURL(AppLinks.appStoreURL)
            } label: {
                Text("Update On Board")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled()
    }
}

#Preview {
    NavigationStack { OnboardingUpdateRequiredView() }
}
```

- [ ] **Step 6: Add the App Store link constant**

`AppLinks` has no App Store URL today. Add one to
`On Board/Configuration/AppLinks.swift`, after `termsOfServiceURL`, matching the
existing `static let` style:

```swift
    /// App Store product page, used by update prompts.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id000000000")!
```

> **`000000000` is a placeholder and must be replaced before this build ships.**
> The real Apple ID is in App Store Connect under App Information → General
> Information → Apple ID. A wrong ID sends users to a 404 at the exact moment
> they are already stuck and cannot use the app.

- [ ] **Step 7: Route `.unrecognized` in the coordinator**

In `On Board/Onboarding/OnboardingCoordinator.swift`, in `effectiveStep` (line 41), add the guard as the **first** statement inside the computed property, before the `hasCompletedProfanityStep` check:

```swift
    private var effectiveStep: OnboardingStep {
        guard let status = onboarding.status else { return .birthday }
        let backendStep = status.effectiveOnboardingStep
        // A step this build doesn't recognize short-circuits everything below —
        // the client-inserted steps and rank() arithmetic are meaningless once
        // the server is running a flow we don't know.
        if backendStep == .unrecognized { return .unrecognized }
        // .contentPreferences has no backing DB state, so it can't come back from
        // effectiveOnboardingStep — insert it locally once profile is behind the
        // user and it hasn't been shown yet.
        if !hasCompletedProfanityStep, Self.rank(backendStep) > Self.rank(.profile) {
            return .contentPreferences
        }
        // .graduation is also client-inserted: shown right after school
        // verification while `expected_graduation` is still null. Existing users
        // were backfilled to a value, so they never see it.
        if status.verifiedSchoolEmail != nil, status.expectedGraduation == nil {
            return .graduation
        }
        return backendStep
    }
```

Then add a case to the `navigationDestination(for: OnboardingStep.self)` switch (starts line 69), alongside the other step cases:

```swift
                        case .unrecognized:
                            OnboardingUpdateRequiredView()
```

- [ ] **Step 8: Verify the build and run the full suite**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`

Expected: `** BUILD SUCCEEDED **`. A non-exhaustive-switch error here means another `switch` over `OnboardingStep` exists — add `.unrecognized` there too, routing to the same view or to a no-op.

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`

Expected: PASS, whole suite. `OnboardingStoreTests` must be unaffected — if a test fails on step ordering, the manual `allCases` in Step 3 is wrong.

- [ ] **Step 9: Commit**

```bash
git add "On Board/Models/OnboardingStep.swift" "On Board/Views/Onboarding/OnboardingUpdateRequiredView.swift" "On Board/Onboarding/OnboardingCoordinator.swift" "On Board/Configuration/AppLinks.swift" "On BoardTests/WireEnumDecodingTests.swift"
git commit -m "Stop onboarding with an update prompt on an unrecognized step"
```

---

### Task 6: Document the convention

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing in code.

Without this, the next enum added to the wire reintroduces the bug. This is the task that makes the fix stick.

- [ ] **Step 1: Add the convention to CLAUDE.md**

In `CLAUDE.md`, under **Key Conventions**, add:

```markdown
- **Every enum that crosses the Supabase wire must decode unknown values, never
  throw.** These are decoded inside arrays (`[RemotePostRow]`,
  `[UserReactionRow]`, `[UserCommentVoteRow]`), so one unrecognized value fails
  the *entire* response — a tone added in a future build would blank the whole
  feed for every client that hadn't updated, for a week, with the content gone at
  the next reset. Pick the fallback by semantics, don't default it:
  `PostTone` maps deterministically to a known tone via `StableHash`; `Reaction`
  and `CommentVote` rows carry a raw `String` and are dropped at mapping time
  (mapping an unknown reaction onto a known one would inflate its count);
  `BoardWeek.Status` degrades to `.archived` (read-only); `OnboardingStep`
  decodes to `.unrecognized` and routes to `OnboardingUpdateRequiredView`,
  because admitting a half-onboarded user or trapping them in a loop are both
  worse than stopping. `AuthProvider` needs nothing — every wire path already
  goes through the failable `init?(supabaseProvider:)`.
  `WireEnumDecodingTests` pins all of it, including that `.unrecognized` stays
  out of `OnboardingStep.allCases` (`rank(_:)` and `OnboardingProgressBar` index
  off it).
- **Never use `String.hashValue` for anything persisted, rendered, or bucketed.**
  Swift seeds it per process, so the same input yields a different result after
  every launch — an unknown post tone would change color on every cold start.
  Use `StableHash.fnv1a` (`Extensions/StableHash.swift`).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the forward-compatible wire enum convention"
```

---

## Verification

After all six tasks:

- [ ] `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build` → `** BUILD SUCCEEDED **`
- [ ] Full suite passes with `-parallel-testing-enabled NO`
- [ ] Manual simulator check: the app launches, the feed loads, a post opens, a reaction and a comment vote both register. These paths all changed shape and none is covered end-to-end by a unit test.
- [ ] `AppLinks.appStoreURL` contains the **real** Apple ID, not the `000000000` placeholder.

## Deliberately not in this plan

- The config-driven version gate, feature flags, and remote constants — separate plan, same target build.
- Observability/Sentry — separate plan.
- Any change to `RemotePostRow.decodeReactionCounts`, which is already lenient, or to `AuthProvider`, which is already safe on every wire path.
