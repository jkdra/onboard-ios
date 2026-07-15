# Client-Side Cache & Speedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate loading spinners for data already seen this session or a prior one (board feed, Pop Score, comments, notification settings) by hydrating `BoardStore` from a single on-disk cache file before any network fetch, revalidating in the background, and making notification-settings saves optimistic with rollback + alerting.

**Architecture:** A new `CacheEnvelope` (`Codable`) holds everything cached to disk — the active board's `BoardSnapshot`, archived-week metadata, Pop Scores, comments, and notification settings — written to one JSON file via the existing `BoardJSON.encoder`/`.decoder`. `BoardStore.refresh(for:)` hydrates from that file before its existing `hasCachedFeed` check, so the current spinner-skip logic works unchanged. Every mutating operation (block/unblock, notification-settings save) persists the updated state; sign-out clears the file outright.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`/`@MainActor` (`BoardStore`), Swift Testing (`@Test`/`#expect`), `FileManager`/`JSONEncoder`/`JSONDecoder` for the disk cache (no SwiftData/CoreData).

## Global Constraints

- No offline read/write support — network is still required for anything not already cached. This is purely about not re-showing a spinner for already-seen data.
- No disk persistence for archived-week content — only the active week's snapshot persists to disk.
- `ProfileView`'s live `isFollowing` check must NOT be folded into this cache — it is a documented, intentional exception.
- Reads that revalidate already-cached data fail silently. Writes that fail always roll back and surface an alert.
- One envelope, one file. Adding a new cached entity type means adding one `Optional`-safe field to `CacheEnvelope`, not a new mechanism.
- Any decode failure (corrupt JSON, mismatched `schemaVersion`) is treated as a cache miss — delete the file, fall through to normal loading. Never crash on a bad cache file.
- Spec: `docs/superpowers/specs/2026-07-14-client-cache-speedup-design.md`.
- Phase 3 (server-side Pop Score denormalization, Task 9 below) touches the live Supabase project's schema and must NOT be applied without explicit user confirmation, separate from the rest of this plan.

---

## Task 1: `CacheEnvelope` and `BoardSnapshot` Codable conformance

**Files:**
- Create: `On Board/Store/CacheEnvelope.swift`
- Modify: `On Board/Supabase/BoardService.swift:11-16`
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `struct CacheEnvelope: Codable` with `static let currentSchemaVersion: Int`, and stored properties `schemaVersion: Int`, `cachedAt: Date`, `boardID: UUID`, `snapshot: BoardSnapshot`, `archivedWeeks: [BoardWeek]`, `popScores: [UUID: [Reaction: Int]]`, `comments: [UUID: [Comment]]`, `commentVotes: [UUID: CommentVote]`, `notificationSettings: NotificationSettings?`.
- Produces: `BoardSnapshot: Sendable, Codable` (was `Sendable` only).
- Consumes: `BoardJSON.encoder` / `BoardJSON.decoder` (`On Board/Supabase/BoardJSON.swift`).

- [ ] **Step 1: Write the failing test**

Add to `On BoardTests/On_BoardTests.swift`, near the other `*CodingTests` suites (after `TagRowCodingTests`, before `NotificationSettingsPayloadTests`):

```swift
struct CacheEnvelopeCodingTests {
    @Test @MainActor func roundTripsThroughBoardJSON() throws {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let post = Post(
            boardWeekId: week.id,
            title: "cached post",
            description: "d",
            author: profile.handle,
            authorId: profile.id
        )
        let envelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion,
            cachedAt: .now,
            boardID: boardID,
            snapshot: BoardSnapshot(
                week: week,
                posts: [post],
                profiles: [profile],
                userReactions: [post.id: .like]
            ),
            archivedWeeks: [],
            popScores: [profile.id: [.like: 3, .hug: 1]],
            comments: [:],
            commentVotes: [:],
            notificationSettings: NotificationSettings(pushComments: false)
        )

        let data = try BoardJSON.encoder.encode(envelope)
        let decoded = try BoardJSON.decoder.decode(CacheEnvelope.self, from: data)

        #expect(decoded.schemaVersion == envelope.schemaVersion)
        #expect(decoded.boardID == boardID)
        #expect(decoded.snapshot.week.id == week.id)
        #expect(decoded.snapshot.posts.first?.id == post.id)
        #expect(decoded.popScores[profile.id]?[.like] == 3)
        #expect(decoded.notificationSettings?.pushComments == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/CacheEnvelopeCodingTests/roundTripsThroughBoardJSON"`
Expected: FAIL — `Cannot find 'CacheEnvelope' in scope` (build error, not a test failure yet).

> If that destination errors with "Unable to find a device matching the provided destination specifier", run `xcrun simctl list devices available` and substitute `-destination "id=<UDID>"` for any available iOS 18 simulator — this is a known simulator-availability quirk, not a plan issue.

- [ ] **Step 3: Create `CacheEnvelope.swift`**

```swift
//
//  CacheEnvelope.swift
//  On Board
//
//  Everything BoardStore persists to disk so a warm relaunch can paint
//  before the network responds. One file, one shape — see the
//  "Client-Side Cache" section of CLAUDE.md before adding a new field.
//

import Foundation

struct CacheEnvelope: Codable {
    /// Bump only when an existing field's *meaning* changes in a way old
    /// data would misrepresent — adding a new Optional field does not
    /// require a bump. A mismatch is treated as a cache miss, never
    /// partially decoded.
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let cachedAt: Date
    let boardID: UUID
    let snapshot: BoardSnapshot
    let archivedWeeks: [BoardWeek]
    let popScores: [UUID: [Reaction: Int]]
    let comments: [UUID: [Comment]]
    let commentVotes: [UUID: CommentVote]
    let notificationSettings: NotificationSettings?
}
```

- [ ] **Step 4: Make `BoardSnapshot` Codable**

In `On Board/Supabase/BoardService.swift:11`, change:

```swift
struct BoardSnapshot: Sendable {
```

to:

```swift
struct BoardSnapshot: Sendable, Codable {
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/CacheEnvelopeCodingTests/roundTripsThroughBoardJSON"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add "On Board/Store/CacheEnvelope.swift" "On Board/Supabase/BoardService.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Add CacheEnvelope and make BoardSnapshot Codable"
```

---

## Task 2: `BoardStore+DiskCache.swift` — hydrate / persist / clear

**Files:**
- Create: `On Board/Store/BoardStore+DiskCache.swift`
- Modify: `On Board/Store/BoardStore.swift:62-64` (new stored properties), `On Board/Store/BoardStore.swift:189-211` (`resetForSignOut`)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Consumes: `BoardStore.apply(_:incomingArchivedWeeks:)` (`BoardStore.swift:288`), `BoardStore.posts/profiles/activeBoardWeek/userReactions/archivedWeeks/commentsByPostID/userCommentVotes` (all existing).
- Produces: `BoardStore.hydrateFromDiskIfNeeded(boardID: UUID)`, `BoardStore.persistToDisk()`, `BoardStore.clearDiskCache()`, `BoardStore.cacheFileURL: URL` (static, internal — exposed for test access, not `private`).
- Produces: new stored properties `BoardStore.popScores: [UUID: [Reaction: Int]]`, `BoardStore.notificationSettings: NotificationSettings?`, `BoardStore.notificationSettingsSaveError: PresentableAlertError?`, `@ObservationIgnored BoardStore.notificationSettingsSyncTask: Task<Void, Never>?`.

- [ ] **Step 1: Write the failing tests**

Add to `On BoardTests/On_BoardTests.swift`, inside (or right after) `struct BoardStoreTests { ... }`:

```swift
extension BoardStoreTests {
    @Test @MainActor func hydrateFromDiskRestoresWarmState() {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let post = Post(
            boardWeekId: week.id,
            title: "cached",
            description: "d",
            author: profile.handle,
            authorId: profile.id
        )
        let writer = BoardStore(
            posts: [post],
            profiles: [profile],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test")
        )
        writer.persistToDisk()
        defer { writer.clearDiskCache() }

        let reader = BoardStore()
        reader.hydrateFromDiskIfNeeded(boardID: boardID)

        #expect(reader.activeBoardWeek?.boardId == boardID)
        #expect(reader.posts.contains { $0.id == post.id })
        #expect(reader.profile(id: profile.id)?.id == profile.id)
    }

    @Test @MainActor func mismatchedSchemaVersionIsTreatedAsMiss() throws {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let staleEnvelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion + 1,
            cachedAt: .now,
            boardID: boardID,
            snapshot: BoardSnapshot(week: week, posts: [], profiles: [], userReactions: [:]),
            archivedWeeks: [],
            popScores: [:],
            comments: [:],
            commentVotes: [:],
            notificationSettings: nil
        )
        let data = try BoardJSON.encoder.encode(staleEnvelope)
        try data.write(to: BoardStore.cacheFileURL, options: .atomic)

        let reader = BoardStore()
        reader.hydrateFromDiskIfNeeded(boardID: boardID)

        #expect(reader.activeBoardWeek == nil)
        #expect(!FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))
    }

    @Test @MainActor func clearDiskCacheRemovesFile() {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let store = BoardStore(
            posts: [],
            profiles: [],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test")
        )
        store.persistToDisk()
        #expect(FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))

        store.clearDiskCache()
        #expect(!FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests"`
Expected: FAIL — `Cannot find 'hydrateFromDiskIfNeeded'`/`'persistToDisk'`/`'clearDiskCache'`/`'cacheFileURL'` in scope.

- [ ] **Step 3: Add new stored properties to `BoardStore.swift`**

In `On Board/Store/BoardStore.swift`, change line 63 from:

```swift
    var followedUserIDs: Set<UUID> = []
```

to:

```swift
    var followedUserIDs: Set<UUID> = []
    /// Pop Score per profile, keyed by user ID — moved here from ProfileView's
    /// local @State so it's cacheable and prefetchable. See BoardStore+Profiles.swift.
    var popScores: [UUID: [Reaction: Int]] = [:]
    var notificationSettings: NotificationSettings?
    /// Surfaces a failed notification-settings save as an alert. Deliberately
    /// separate from `loadError`, which is about board-loading failures.
    var notificationSettingsSaveError: PresentableAlertError?
```

Then, right after line 93 (`@ObservationIgnored var commentVoteSyncTasks: [UUID: Task<Void, Never>] = [:]`), add:

```swift
    // One in-flight notification-settings save. A rapid second toggle
    // supersedes the first so its rollback can't invert newer state.
    @ObservationIgnored var notificationSettingsSyncTask: Task<Void, Never>?
```

- [ ] **Step 4: Clear the new state in `resetForSignOut()`**

In `On Board/Store/BoardStore.swift:189-211`, change:

```swift
    func resetForSignOut() {
        posts = []
        profiles = []
        boardWeeks = []
        activeBoardWeek = nil
        currentBoard = nil
        accessibleBoards = []
        currentUserID = nil
        userReactions = [:]
        userCommentVotes = [:]
        blockedUserIDs = []
        followedUserIDs = []
        postProxies = [:]
        commentsByPostID = [:]
        cachedArchiveWeekIDs = []
        loadError = nil
        // Previously only cleared postsByID (as a side effect of
        // clearFeedItemsCache()) — postsByWeek, profileIndex, and archivedWeeks
        // were left stale from the prior session. All the source arrays above
        // are already empty, so rebuilding here is cheap and correctly zeroes
        // every derived index.
        rebuildCaches()
    }
```

to:

```swift
    func resetForSignOut() {
        posts = []
        profiles = []
        boardWeeks = []
        activeBoardWeek = nil
        currentBoard = nil
        accessibleBoards = []
        currentUserID = nil
        userReactions = [:]
        userCommentVotes = [:]
        blockedUserIDs = []
        followedUserIDs = []
        postProxies = [:]
        commentsByPostID = [:]
        cachedArchiveWeekIDs = []
        loadError = nil
        popScores = [:]
        notificationSettings = nil
        notificationSettingsSaveError = nil
        notificationSettingsSyncTask?.cancel()
        notificationSettingsSyncTask = nil
        // A cached board/profile/settings blob must never leak into a
        // different account signing into the same device.
        clearDiskCache()
        // Previously only cleared postsByID (as a side effect of
        // clearFeedItemsCache()) — postsByWeek, profileIndex, and archivedWeeks
        // were left stale from the prior session. All the source arrays above
        // are already empty, so rebuilding here is cheap and correctly zeroes
        // every derived index.
        rebuildCaches()
    }
```

- [ ] **Step 5: Create `BoardStore+DiskCache.swift`**

```swift
//
//  BoardStore+DiskCache.swift
//  On Board
//
//  A single on-disk CacheEnvelope so a warm relaunch can paint before the
//  network responds. See the "Client-Side Cache" section of CLAUDE.md.
//

import Foundation

extension BoardStore {
    /// Not `private` — the test target reads/writes this path directly to
    /// seed and verify cache fixtures without exercising the full app.
    static var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("org.onboardapp.board-cache.json")
    }

    /// Hydrates in-memory state from disk if this board isn't already warm.
    /// Call before any "is the cache warm" check (e.g. `refresh(for:)`'s
    /// `hasCachedFeed`) so a successful hydration skips the loading spinner
    /// for free. Any decode failure (corrupt file, mismatched schema version,
    /// or a different board's cache) is treated as a plain cache miss — the
    /// file is deleted and normal network loading proceeds.
    func hydrateFromDiskIfNeeded(boardID: UUID) {
        guard !(activeBoardWeek?.boardId == boardID && !posts.isEmpty) else { return }
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let envelope = try? BoardJSON.decoder.decode(CacheEnvelope.self, from: data),
              envelope.schemaVersion == CacheEnvelope.currentSchemaVersion,
              envelope.boardID == boardID
        else {
            try? FileManager.default.removeItem(at: Self.cacheFileURL)
            return
        }
        apply(envelope.snapshot, incomingArchivedWeeks: envelope.archivedWeeks)
        popScores = envelope.popScores
        commentsByPostID = envelope.comments
        userCommentVotes = envelope.commentVotes
        notificationSettings = envelope.notificationSettings
    }

    /// Best-effort disk write of everything currently cacheable. Call after
    /// any successful board load and after any mutation that changes cached
    /// state (block/unblock, notification-settings save) — don't rely solely
    /// on the next natural refresh to capture a mutation, since a force-quit
    /// in between would leave stale content cached. A write failure only
    /// costs a future cold-launch spinner, never correctness.
    func persistToDisk() {
        guard let activeBoardWeek else { return }
        let activeWeekPosts = posts.filter { $0.boardWeekId == activeBoardWeek.id }
        let snapshot = BoardSnapshot(
            week: activeBoardWeek,
            posts: activeWeekPosts,
            profiles: profiles,
            userReactions: userReactions
        )
        let envelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion,
            cachedAt: .now,
            boardID: activeBoardWeek.boardId,
            snapshot: snapshot,
            archivedWeeks: archivedWeeks,
            popScores: popScores,
            comments: commentsByPostID,
            commentVotes: userCommentVotes,
            notificationSettings: notificationSettings
        )
        guard let data = try? BoardJSON.encoder.encode(envelope) else { return }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
    }

    /// Deletes the cache file. Called on sign-out — a cached board/profile/
    /// settings blob must never leak into a different account's session.
    func clearDiskCache() {
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests"`
Expected: PASS (all `BoardStoreTests`, including the three new ones)

- [ ] **Step 7: Commit**

```bash
git add "On Board/Store/BoardStore.swift" "On Board/Store/BoardStore+DiskCache.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Add BoardStore disk cache (hydrate/persist/clear)"
```

---

## Task 3: Wire the disk cache into `refresh(for:)` and blocking

**Files:**
- Modify: `On Board/Store/BoardStore+Refresh.swift:33-101` (`refresh(for:)`)
- Modify: `On Board/Store/BoardStore+Moderation.swift:72-106` (`block`, `unblock`)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Consumes: `hydrateFromDiskIfNeeded(boardID:)`, `persistToDisk()` (Task 2).
- Produces: no new public API — behavioral wiring only.

- [ ] **Step 1: Write the failing test**

Add to `On BoardTests/On_BoardTests.swift`, inside `extension BoardStoreTests`:

```swift
    @Test @MainActor func refreshHydratesFromDiskBeforeNetworkFails() async {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let post = Post(
            boardWeekId: week.id,
            title: "cached",
            description: "d",
            author: profile.handle,
            authorId: profile.id
        )
        let writer = BoardStore(
            posts: [post],
            profiles: [profile],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test")
        )
        writer.persistToDisk()
        defer { writer.clearDiskCache() }

        let reader = BoardStore(
            posts: [],
            profiles: [],
            currentUserID: UUID(),
            currentBoard: Board(id: boardID, name: "Test"),
            boardService: MockBoardService()
        )

        // MockBoardService.loadActiveBoard always throws .notConfigured. Without
        // the hydrate-before-check wiring this task adds, reader.posts would stay
        // empty since apply() only ever writes on success.
        await reader.refresh(for: reader.currentUserID)

        #expect(reader.activeBoardWeek?.boardId == boardID)
        #expect(reader.posts.contains { $0.id == post.id })
        #expect(reader.loadError != nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/refreshHydratesFromDiskBeforeNetworkFails"`
Expected: FAIL — `reader.posts.contains { ... }` is false (cache never hydrated).

- [ ] **Step 3: Wire hydration and persistence into `refresh(for:)`**

In `On Board/Store/BoardStore+Refresh.swift:33-101`, change:

```swift
    func refresh(for userID: UUID?) async {
        guard let boardService, let userID else { return }
        // Never fall back to the sample/dev board on live paths: no assigned
        // board means there is nothing to fetch yet (waitlisted user).
        guard let boardID = currentBoardId else { return }

        if let inFlight = refreshTask {
            if refreshTaskBoardID == boardID {
                await inFlight.value
                return
            }
            // The in-flight load is for a different board (user switched mid-load).
            // Supersede it: cancel, wait it out, then load the selected board.
            inFlight.cancel()
            await inFlight.value
        }

        // Only treat the cache as warm when it belongs to the board being fetched —
        // on a board switch the old board's feed must not suppress the loading state.
        let hasCachedFeed = activeBoardWeek?.boardId == boardID && !posts.isEmpty
```

to:

```swift
    func refresh(for userID: UUID?) async {
        guard let boardService, let userID else { return }
        // Never fall back to the sample/dev board on live paths: no assigned
        // board means there is nothing to fetch yet (waitlisted user).
        guard let boardID = currentBoardId else { return }

        if let inFlight = refreshTask {
            if refreshTaskBoardID == boardID {
                await inFlight.value
                return
            }
            // The in-flight load is for a different board (user switched mid-load).
            // Supersede it: cancel, wait it out, then load the selected board.
            inFlight.cancel()
            await inFlight.value
        }

        // A warm hydration below can make hasCachedFeed true "for free," which
        // is exactly how a relaunch skips the loading spinner without any
        // change to the gating logic itself.
        hydrateFromDiskIfNeeded(boardID: boardID)

        // Only treat the cache as warm when it belongs to the board being fetched —
        // on a board switch the old board's feed must not suppress the loading state.
        let hasCachedFeed = activeBoardWeek?.boardId == boardID && !posts.isEmpty
```

Then, still in `refresh(for:)`, change:

```swift
                    apply(try await snapshot, incomingArchivedWeeks: try await archivedWeeks)
                    await refreshAccessibleBoards(for: userID)
                    await refreshBlockedUsers(for: userID)
                    await refreshFollowedUsers(for: userID)
                    break
```

to:

```swift
                    apply(try await snapshot, incomingArchivedWeeks: try await archivedWeeks)
                    persistToDisk()
                    await refreshAccessibleBoards(for: userID)
                    await refreshBlockedUsers(for: userID)
                    await refreshFollowedUsers(for: userID)
                    break
```

- [ ] **Step 4: Persist after block/unblock succeed**

In `On Board/Store/BoardStore+Moderation.swift:72-93`, change:

```swift
    func block(userID: UUID) async throws {
        guard userID != currentUserID else { return }
        guard let boardService else { throw BoardServiceError.notConfigured }

        // Snapshot for rollback.
        let priorBlocked = blockedUserIDs
        let priorPosts = posts
        let priorComments = commentsByPostID

        blockedUserIDs.insert(userID)
        removeContentLocally(byAuthor: userID)

        do {
            try await boardService.blockUser(blockedID: userID)
        } catch {
            blockedUserIDs = priorBlocked
            posts = priorPosts
            commentsByPostID = priorComments
            rebuildCaches()
            throw error
        }
    }
```

to:

```swift
    func block(userID: UUID) async throws {
        guard userID != currentUserID else { return }
        guard let boardService else { throw BoardServiceError.notConfigured }

        // Snapshot for rollback.
        let priorBlocked = blockedUserIDs
        let priorPosts = posts
        let priorComments = commentsByPostID

        blockedUserIDs.insert(userID)
        removeContentLocally(byAuthor: userID)

        do {
            try await boardService.blockUser(blockedID: userID)
            // A force-quit right after blocking must not leave stale
            // (unblocked) content cached — don't rely solely on the next
            // natural refresh to capture this.
            persistToDisk()
        } catch {
            blockedUserIDs = priorBlocked
            posts = priorPosts
            commentsByPostID = priorComments
            rebuildCaches()
            throw error
        }
    }
```

And change:

```swift
    func unblock(userID: UUID) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        let priorBlocked = blockedUserIDs
        blockedUserIDs.remove(userID)
        do {
            try await boardService.unblockUser(blockedID: userID)
        } catch {
            blockedUserIDs = priorBlocked
            throw error
        }
    }
```

to:

```swift
    func unblock(userID: UUID) async throws {
        guard let boardService else { throw BoardServiceError.notConfigured }
        let priorBlocked = blockedUserIDs
        blockedUserIDs.remove(userID)
        do {
            try await boardService.unblockUser(blockedID: userID)
            persistToDisk()
        } catch {
            blockedUserIDs = priorBlocked
            throw error
        }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/refreshHydratesFromDiskBeforeNetworkFails"`
Expected: PASS

- [ ] **Step 6: Run the full test suite to check for regressions**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add "On Board/Store/BoardStore+Refresh.swift" "On Board/Store/BoardStore+Moderation.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Hydrate BoardStore from disk cache on refresh; persist after block/unblock"
```

---

## Task 4: Pop Score moves into `BoardStore`, with tap-intent prefetch

**Files:**
- Modify: `On Board/Store/BoardStore+Profiles.swift`
- Modify: `On Board/Views/Profile/ProfileView.swift:47-49,138-159,190-198`
- Modify: `On Board/Views/Post/PostDetailView.swift:158-162`
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Produces: `BoardStore.popScore(for userID: UUID) -> [Reaction: Int]?`, `BoardStore.refreshPopScore(for userID: UUID) async`, `BoardStore.prefetchPopScore(for userID: UUID)`.
- Consumes: `BoardStore.popScores` (Task 2), `BoardStore.persistToDisk()` (Task 2), `boardService.fetchUserReactionCounts(for:)` (`BoardService.swift:108`).

- [ ] **Step 1: Write the failing test**

Add to `On BoardTests/On_BoardTests.swift`. First, give `MockBoardService` a way to return real counts instead of always `[:]` — change:

```swift
    func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int] { [:] }
```

to:

```swift
    var stubbedReactionCounts: [Reaction: Int] = [:]
    func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int] { stubbedReactionCounts }
```

Then add a new test, inside `extension BoardStoreTests`:

```swift
    @Test @MainActor func refreshPopScorePopulatesCacheAndPersists() async {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let service = MockBoardService()
        service.stubbedReactionCounts = [.like: 5, .laugh: 2]
        let store = BoardStore(
            posts: [],
            profiles: [profile],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test"),
            boardService: service
        )
        defer { store.clearDiskCache() }

        #expect(store.popScore(for: profile.id) == nil)
        await store.refreshPopScore(for: profile.id)
        #expect(store.popScore(for: profile.id)?[.like] == 5)
        #expect(store.popScore(for: profile.id)?[.laugh] == 2)

        // Rehydrating a fresh store from the disk cache should see the same score.
        let reader = BoardStore()
        reader.hydrateFromDiskIfNeeded(boardID: boardID)
        #expect(reader.popScore(for: profile.id)?[.like] == 5)
    }
```

`MockBoardService` is declared `private final class` inside `On BoardTests/On_BoardTests.swift`, so adding the `stubbedReactionCounts` var is a same-file edit (no access-level changes needed since the new test is in the same file).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/refreshPopScorePopulatesCacheAndPersists"`
Expected: FAIL — `Cannot find 'popScore'`/`'refreshPopScore'` in scope.

- [ ] **Step 3: Add Pop Score methods to `BoardStore+Profiles.swift`**

Append to `On Board/Store/BoardStore+Profiles.swift` (inside the existing `extension BoardStore { ... }`, after `unfollowUser`):

```swift

    // MARK: - Pop Score

    func popScore(for userID: UUID) -> [Reaction: Int]? {
        popScores[userID]
    }

    /// Fetches (or, offline, locally aggregates) a profile's Pop Score and
    /// caches it. A revalidation failure is silent — the caller already has
    /// whatever was cached before, if anything, matching the read-vs-write
    /// failure rule (reads that revalidate fail silently; only writes alert).
    func refreshPopScore(for userID: UUID) async {
        if let boardService {
            guard let fetched = try? await boardService.fetchUserReactionCounts(for: userID) else { return }
            popScores[userID] = fetched
        } else {
            // Offline/mock mode has no live service to aggregate reactions
            // server-side, so approximate it from the posts already in memory.
            popScores[userID] = posts
                .filter { $0.authorId == userID }
                .reduce(into: [Reaction: Int]()) { counts, post in
                    for (reaction, count) in post.reactionCounts {
                        counts[reaction, default: 0] += count
                    }
                }
        }
        persistToDisk()
    }

    /// No-op if already warm. Called from PostDetailView on open, so a
    /// tapped-into post's author's Pop Score is ready before (if ever) the
    /// user taps through to that profile.
    func prefetchPopScore(for userID: UUID) {
        guard popScores[userID] == nil else { return }
        Task { await refreshPopScore(for: userID) }
    }
```

- [ ] **Step 4: Update `ProfileView.swift` to read/refresh through the store**

In `On Board/Views/Profile/ProfileView.swift`, remove the local Pop Score state — change:

```swift
    // Pop Score
    @State private var popScore: [Reaction: Int]?
    @State private var isLoadingPopScore = false
```

to nothing (delete these two lines entirely).

Change the Pop Score `.task` (lines 138-159):

```swift
            .task {
                guard popScore == nil, !isLoadingPopScore else { return }
                isLoadingPopScore = true
                if let boardService = store.boardService {
                    do {
                        popScore = try await boardService.fetchUserReactionCounts(for: profile.id)
                    } catch {
                        // Failed silently for now
                    }
                } else {
                    // Offline/mock mode has no live service to aggregate reactions
                    // server-side, so approximate it from the posts already in memory.
                    popScore = store.posts
                        .filter { $0.authorId == profile.id }
                        .reduce(into: [Reaction: Int]()) { counts, post in
                            for (reaction, count) in post.reactionCounts {
                                counts[reaction, default: 0] += count
                            }
                        }
                }
                isLoadingPopScore = false
            }
```

to:

```swift
            .task(id: profile.id) {
                await store.refreshPopScore(for: profile.id)
            }
```

Change the render site (lines 188-199):

```swift
                    if !editMode {
                        if !isBlockedByMe {
                            if let popScore {
                                PopScoreView(score: popScore)
                                    .padding(.top, 8)
                                    .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                            } else if isLoadingPopScore {
                                ProgressView()
                                    .padding(.top, 8)
                                    .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                            }
                        }
```

to:

```swift
                    if !editMode {
                        if !isBlockedByMe {
                            if let popScore = store.popScore(for: profile.id) {
                                PopScoreView(score: popScore)
                                    .padding(.top, 8)
                                    .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                            } else {
                                ProgressView()
                                    .padding(.top, 8)
                                    .matchedGeometryEffect(id: "popScore", in: profileNamespace)
                            }
                        }
```

- [ ] **Step 5: Add the prefetch hook to `PostDetailView.swift`**

In `On Board/Views/Post/PostDetailView.swift:158-162`, change:

```swift
        .task(id: livePost.id) {
            isLoadingComments = true
            await store.loadComments(for: livePost.id)
            isLoadingComments = false
        }
```

to:

```swift
        .task(id: livePost.id) {
            isLoadingComments = true
            await store.loadComments(for: livePost.id)
            isLoadingComments = false
        }
        .task(id: livePost.id) {
            guard let authorId = livePost.authorId else { return }
            store.prefetchPopScore(for: authorId)
        }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/refreshPopScorePopulatesCacheAndPersists"`
Expected: PASS

- [ ] **Step 7: Build the app target to confirm the view changes compile**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add "On Board/Store/BoardStore+Profiles.swift" "On Board/Views/Profile/ProfileView.swift" "On Board/Views/Post/PostDetailView.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Move Pop Score into BoardStore; prefetch on post-detail open"
```

---

## Task 5: Comments join the cache; revalidation fails silently

**Files:**
- Modify: `On Board/Store/BoardStore+Refresh.swift:168-182` (`loadComments`)
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Consumes: `commentsByPostID` (existing), `Self.mapLoadError` (existing).
- Produces: no signature change to `loadComments(for:)` — behavior only.

- [ ] **Step 1: Write the failing test**

Add to `On BoardTests/On_BoardTests.swift`. First, give `MockBoardService.fetchComments` a way to fail on demand — change:

```swift
    func fetchComments(for postID: UUID) async throws -> CommentThread { throw BoardServiceError.notConfigured }
```

to:

```swift
    var commentsShouldFail = false
    func fetchComments(for postID: UUID) async throws -> CommentThread {
        if commentsShouldFail { throw BoardServiceError.notConfigured }
        return CommentThread(comments: [], userVotes: [:])
    }
```

Then add:

```swift
    @Test @MainActor func loadCommentsRevalidationFailsSilentlyWhenAlreadyWarm() async {
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let post = Post(boardWeekId: activeWeek.id, title: "t", description: "d", author: "maya.c", comments: [.authored(by: "maya.c", body: "hi")])
        let service = MockBoardService()
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: service
        )

        service.commentsShouldFail = true
        await store.loadComments(for: post.id)

        // Comments were already cached (from the convenience init, which seeds
        // commentsByPostID from any post.comments) — a background revalidation
        // failure must not surface loadError.
        #expect(store.loadError == nil)
    }

    @Test @MainActor func loadCommentsColdFailureSurfacesLoadError() async {
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let post = Post(boardWeekId: activeWeek.id, title: "t", description: "d", author: "maya.c")
        let service = MockBoardService()
        service.commentsShouldFail = true
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: service
        )

        await store.loadComments(for: post.id)

        #expect(store.loadError != nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/loadCommentsRevalidationFailsSilentlyWhenAlreadyWarm"`
Expected: FAIL — `store.loadError == nil` is false (today's `loadComments` always sets `loadError` on failure, warm or cold).

- [ ] **Step 3: Make `loadComments(for:)` silent on revalidation**

In `On Board/Store/BoardStore+Refresh.swift:168-182`, change:

```swift
    func loadComments(for postID: UUID) async {
        guard let boardService else { return }
        guard posts.contains(where: { $0.id == postID }) else { return }

        do {
            let thread = try await boardService.fetchComments(for: postID)
            commentsByPostID[postID] = thread.comments
            for (commentID, vote) in thread.userVotes {
                userCommentVotes[commentID] = vote
            }
            await loadMissingCommentAuthorProfiles(in: thread.comments)
        } catch {
            loadError = Self.mapLoadError(error)
        }
    }
```

to:

```swift
    func loadComments(for postID: UUID) async {
        guard let boardService else { return }
        guard posts.contains(where: { $0.id == postID }) else { return }

        // A post already showing cached comments is a background revalidation —
        // fail silently, matching the read-vs-write rule (reads that revalidate
        // already-cached data fail silently; only writes alert). A post with no
        // cached comments yet is a true first load, so its failure still surfaces.
        let isRevalidation = commentsByPostID[postID] != nil

        do {
            let thread = try await boardService.fetchComments(for: postID)
            commentsByPostID[postID] = thread.comments
            for (commentID, vote) in thread.userVotes {
                userCommentVotes[commentID] = vote
            }
            await loadMissingCommentAuthorProfiles(in: thread.comments)
            persistToDisk()
        } catch {
            guard !isRevalidation else { return }
            loadError = Self.mapLoadError(error)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests"`
Expected: PASS (all `BoardStoreTests`, including both new comment tests)

- [ ] **Step 5: Commit**

```bash
git add "On Board/Store/BoardStore+Refresh.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Comments join the disk cache; revalidation failures no longer surface loadError"
```

---

## Task 6: Notification Settings — cache, optimistic save, rollback, alert

**Files:**
- Modify: `On Board/Store/BoardStore+Refresh.swift:229-239` (replace the two thin wrapper methods)
- Modify: `On Board/Views/Settings/NotificationSettingsView.swift`
- Test: `On BoardTests/On_BoardTests.swift`

**Interfaces:**
- Consumes: `BoardStore.notificationSettings`, `BoardStore.notificationSettingsSaveError`, `BoardStore.notificationSettingsSyncTask`, `BoardStore.persistToDisk()` (all Task 2/3).
- Produces: `BoardStore.loadNotificationSettingsIfNeeded() async throws`, `BoardStore.setNotificationSettings(_ newSettings: NotificationSettings)`. Removes: `BoardStore.fetchNotificationSettings() async throws -> NotificationSettings`, `BoardStore.updateNotificationSettings(_:) async throws` (no other call sites — both are only used by `NotificationSettingsView`, updated in this same task).

- [ ] **Step 1: Write the failing tests**

Add to `On BoardTests/On_BoardTests.swift`. First, give `MockBoardService.updateNotificationSettings` a configurable failure — change:

```swift
    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws {}
```

to:

```swift
    var updateNotificationSettingsError: Error?
    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws {
        if let updateNotificationSettingsError { throw updateNotificationSettingsError }
    }
```

Then add:

```swift
    @Test @MainActor func setNotificationSettingsRollsBackAndAlertsOnFailure() async throws {
        let service = MockBoardService()
        let store = BoardStore(
            posts: [],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            boardService: service
        )
        store.notificationSettings = NotificationSettings(pushComments: true)
        service.updateNotificationSettingsError = BoardServiceError.notConfigured

        store.setNotificationSettings(NotificationSettings(pushComments: false))
        #expect(store.notificationSettings?.pushComments == false)

        try await Task.sleep(for: .milliseconds(50))

        #expect(store.notificationSettings?.pushComments == true)
        #expect(store.notificationSettingsSaveError != nil)
    }

    @Test @MainActor func setNotificationSettingsStaleGuardKeepsNewerValue() async throws {
        let service = MockBoardService()
        let store = BoardStore(
            posts: [],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            boardService: service
        )
        store.notificationSettings = NotificationSettings(pushComments: true, pushNewPosts: true)
        service.updateNotificationSettingsError = BoardServiceError.notConfigured

        // First save fails (in flight); before it resolves, a second, newer
        // save supersedes it and succeeds.
        store.setNotificationSettings(NotificationSettings(pushComments: false, pushNewPosts: true))
        service.updateNotificationSettingsError = nil
        store.setNotificationSettings(NotificationSettings(pushComments: false, pushNewPosts: false))

        try await Task.sleep(for: .milliseconds(50))

        // The first save's rollback must not clobber the second (newer) value.
        #expect(store.notificationSettings?.pushNewPosts == false)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/setNotificationSettingsRollsBackAndAlertsOnFailure"`
Expected: FAIL — `Cannot find 'setNotificationSettings'` in scope.

- [ ] **Step 3: Replace the two thin wrapper methods**

In `On Board/Store/BoardStore+Refresh.swift:229-239`, change:

```swift
    // MARK: - Notification Settings

    func fetchNotificationSettings() async throws -> NotificationSettings {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        return try await boardService.fetchNotificationSettings(for: currentUserID)
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async throws {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        try await boardService.updateNotificationSettings(settings, for: currentUserID)
    }
```

to:

```swift
    // MARK: - Notification Settings

    /// Loads settings only if not already cached (from this session or a
    /// disk-hydrated prior one) — a warm value means no spinner is needed, so
    /// this only throws on a true first load with no cache at all. A
    /// revalidation is still kicked off in the background either way, per the
    /// read-vs-write rule: it fails silently if it doesn't turn up anything new.
    func loadNotificationSettingsIfNeeded() async throws {
        guard let boardService, let currentUserID else { throw BoardServiceError.notAuthenticated }
        if notificationSettings == nil {
            notificationSettings = try await boardService.fetchNotificationSettings(for: currentUserID)
            persistToDisk()
        } else {
            Task { await revalidateNotificationSettings() }
        }
    }

    private func revalidateNotificationSettings() async {
        guard let boardService, let currentUserID else { return }
        guard let fetched = try? await boardService.fetchNotificationSettings(for: currentUserID) else { return }
        guard fetched != notificationSettings else { return }
        notificationSettings = fetched
        persistToDisk()
    }

    /// Optimistic save mirroring BoardStore+Reactions.swift's setReaction:
    /// mutate immediately, one in-flight sync task that supersedes itself on
    /// rapid toggles, and a stale-guard so a failed old request can't clobber
    /// an even-newer local change. "Server wins" needs no extra logic beyond
    /// this — any server-confirmed value always overwrites the optimistic guess.
    func setNotificationSettings(_ newSettings: NotificationSettings) {
        let previous = notificationSettings
        guard previous != newSettings else { return }
        notificationSettings = newSettings
        persistToDisk()

        guard let boardService, let currentUserID else { return }
        notificationSettingsSyncTask?.cancel()
        notificationSettingsSyncTask = Task {
            defer { notificationSettingsSyncTask = nil }
            do {
                try await boardService.updateNotificationSettings(newSettings, for: currentUserID)
            } catch {
                if Task.isCancelled { return }
                guard notificationSettings == newSettings else { return }
                notificationSettings = previous
                persistToDisk()
                notificationSettingsSaveError = PresentableAlertError(message: Self.mapLoadError(error))
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/setNotificationSettingsRollsBackAndAlertsOnFailure"`
Expected: PASS

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -only-testing "On BoardTests/On_BoardTests/BoardStoreTests/setNotificationSettingsStaleGuardKeepsNewerValue"`
Expected: PASS

- [ ] **Step 5: Rewrite `NotificationSettingsView.swift`**

Replace the full contents of `On Board/Views/Settings/NotificationSettingsView.swift` with:

```swift
//
//  NotificationSettingsView.swift
//  On Board
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadError: String?
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            if authorizationStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Notifications Disabled", systemImage: "bell.slash.fill")
                            .fontStyle(.headline)
                            .foregroundStyle(.red)
                        
                        Text("You won't receive any push notifications because they are disabled in iOS Settings. Tap below to enable them.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.boardSecondary)
                        .tint(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .fontStyle(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let settings = store.notificationSettings {
                Section {
                    settingsToggle("Reactions", isOn: Binding(
                        get: { settings.pushReactions },
                        set: { store.setNotificationSettings(settings.updating(pushReactions: $0)) }
                    ))
                    settingsToggle("Comments", isOn: Binding(
                        get: { settings.pushComments },
                        set: { store.setNotificationSettings(settings.updating(pushComments: $0)) }
                    ))
                } header: {
                    Text("Your Posts")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("When someone reacts to or comments on something you posted.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts Digest", isOn: Binding(
                        get: { settings.pushNewPosts },
                        set: { store.setNotificationSettings(settings.updating(pushNewPosts: $0)) }
                    ))
                } header: {
                    Text("Board Activity")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A periodic summary of new posts on your board.")
                        .fontStyle(.footnote)
                }

                Section {
                    settingsToggle("New Posts", isOn: Binding(
                        get: { settings.pushFollowedPosts },
                        set: { store.setNotificationSettings(settings.updating(pushFollowedPosts: $0)) }
                    ))
                } header: {
                    Text("People You Follow")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("A push as soon as someone you follow posts.")
                        .fontStyle(.footnote)
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkStatus()
            do {
                try await store.loadNotificationSettingsIfNeeded()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await checkStatus() }
            }
        }
        .presentableErrorAlert(error: saveErrorBinding)
    }

    // Manual Binding against the environment object, matching the idiom used
    // throughout ProfileView/PostDetailView (e.g. PostDetailView's
    // `selectedReaction`) rather than `@Bindable`, which isn't used anywhere
    // else in this codebase.
    private var saveErrorBinding: Binding<PresentableAlertError?> {
        Binding(
            get: { store.notificationSettingsSaveError },
            set: { store.notificationSettingsSaveError = $0 }
        )
    }

    /// Matches the toggle idiom in `SettingsView`: the label carries `.fontStyle(.body)`
    /// (not the Toggle itself) and the switch is tinted `.primary`. Without the tint
    /// these rendered in the default accent green, which is why they looked subtly
    /// different from the toggles on the main Settings screen.
    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).fontStyle(.body)
        }
        .tint(.primary)
    }

    private func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(BoardStore.sampleBoard())
}
```

- [ ] **Step 6: Add the `updating(...)` convenience to `NotificationSettings`**

`Form`/`Toggle` bindings above need a way to produce a copy with one field changed without touching the others. In `On Board/Models/NotificationSettings.swift`, after the closing brace of the `Codable` extension (after line 51), add:

```swift

extension NotificationSettings {
    func updating(
        pushReactions: Bool? = nil,
        pushComments: Bool? = nil,
        pushNewPosts: Bool? = nil,
        pushFollowedPosts: Bool? = nil
    ) -> NotificationSettings {
        NotificationSettings(
            pushReactions: pushReactions ?? self.pushReactions,
            pushComments: pushComments ?? self.pushComments,
            pushNewPosts: pushNewPosts ?? self.pushNewPosts,
            pushFollowedPosts: pushFollowedPosts ?? self.pushFollowedPosts
        )
    }
}
```

- [ ] **Step 7: Build the app target to confirm the view changes compile**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Run the full test suite to check for regressions**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add "On Board/Store/BoardStore+Refresh.swift" "On Board/Views/Settings/NotificationSettingsView.swift" "On Board/Models/NotificationSettings.swift" "On BoardTests/On_BoardTests.swift"
git commit -m "Cache notification settings; make saves optimistic with rollback and alerting"
```

---

## Task 7: CLAUDE.md guardrails

**Files:**
- Modify: `CLAUDE.md:60-62`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Insert the new section**

In `CLAUDE.md`, change:

```markdown
### Optimistic Updates
`BoardStore+Interactions.swift` applies all mutations (reactions, post creation, comments) locally first, then syncs to Supabase. On error it rolls back and surfaces the error. Never skip the rollback path when adding new mutations.

### Navigation Flow
```

to:

```markdown
### Optimistic Updates
`BoardStore+Interactions.swift` applies all mutations (reactions, post creation, comments) locally first, then syncs to Supabase. On error it rolls back and surfaces the error. Never skip the rollback path when adding new mutations.

### Client-Side Cache
`BoardStore` persists a single `CacheEnvelope` (`BoardStore/CacheEnvelope.swift`) to disk via `BoardStore+DiskCache.swift`, after every successful board `apply()` and after any mutation that changes cached state (block/unblock, notification-settings save). `refresh(for:)` hydrates from this file before its `hasCachedFeed` check, so a warm cache skips the loading spinner entirely — no changes needed to `isLoading`'s existing gating.

**Adding a new cached entity**: add one field to `CacheEnvelope`, make it `Optional` (so older cache files still decode), and make sure whatever mutates it in `BoardStore` also calls `persistToDisk()`. Don't invent a second cache mechanism — one envelope, one file.

**Schema drift safety**: any decode failure (bad JSON, mismatched `CacheEnvelope.schemaVersion`) is treated as a cache miss — the file is deleted and normal network loading proceeds. Never crash on a stale/malformed cache file. Bump `schemaVersion` only when an existing field's *meaning* changes in a way old data would misrepresent — adding a new `Optional` field does not require a bump.

**Invalidation correctness**:
- Sign-out calls `clearDiskCache()` (wired into `resetForSignOut()`) — a cached board/profile/settings blob must never leak into a different account's session on the same device.
- Any mutation that changes what's cached (block, unblock, notification-settings save) calls `persistToDisk()` after resolving — don't rely solely on the next natural `refresh()` to capture it, since a force-quit in between would leave stale content cached.

**Known intentional exception — do not cache**: `ProfileView`'s live `isFollowing` check (`.task(id: profile.id)`) deliberately bypasses `followedUserIDs`/any cache and re-queries the server on every profile visit, specifically so a stale cached value can't flip "Following" back to "Follow". Don't fold this into the general cache-everything pattern.

**Read-vs-write failure rule**: background revalidation of already-cached data (Pop Score, comments, notification settings) fails silently — the user already has a value on screen. A failed *write* (a reaction, a notification-settings toggle, anything optimistic) always rolls back and surfaces an alert — never fail a save silently.

### Navigation Flow
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the client-side cache in CLAUDE.md"
```

---

## Task 8: Full verification pass

**Files:** None — build/test only.

- [ ] **Step 1: Clean build**

Run: `xcodebuild -scheme "On Board" -destination "generic/platform=iOS Simulator" build 2>&1 | grep -E "error:|^\*\* BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Manual on-device/simulator smoke check**

Using the `run`/`verify` skill pattern for this project (launch the app in the simulator): sign in with mock data, view a profile with existing posts (Pop Score should render immediately on second visit, no spinner), force-quit and relaunch (feed should paint without a spinner if reopened within the same active week), open Notification Settings twice in a row (second visit should show no spinner), flip a toggle offline/airplane-mode to confirm it rolls back and shows an alert.

- [ ] **Step 4: No commit needed** — this task is verification only.

---

## Task 9 (SEPARATE — requires explicit confirmation before applying): Denormalized Pop Score

**Do not run `mcp__supabase__apply_migration` for this task without first checking in with the user separately from the rest of this plan** — it changes the schema of the live Supabase project, a different risk class than every other task here.

**Files:**
- Create: a new timestamped file under `supabase/migrations/` (gitignored in this repo — author it locally, apply via the Supabase MCP tools, per this repo's documented migration workflow).
- Modify: `On Board/Supabase/SupabaseBoardService+Profiles.swift` (or wherever `fetchUserReactionCounts(for:)` is implemented) — implementation only, signature and every call site (`BoardStore+Profiles.swift`'s `refreshPopScore(for:)`) stay identical.

**Interfaces:** No client-facing API changes — `fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int]` keeps its exact signature.

- [ ] **Step 1: Check current schema before designing the migration**

Use `mcp__supabase__list_tables` to confirm the current `profiles`/`reactions` table shapes before deciding between a maintained `profiles` column vs. a small counts table — this decision was explicitly deferred to implementation time in the design spec (`docs/superpowers/specs/2026-07-14-client-cache-speedup-design.md`, Section 7).

- [ ] **Step 2: Draft the migration locally (do not apply yet)**

Write the migration SQL to a local file under `supabase/migrations/<timestamp>_denormalize_pop_score.sql` for review. It should: add the maintained aggregate (column or table), backfill existing data from the current live-aggregation query, and add a trigger on `reactions` insert/delete/update that keeps it current.

- [ ] **Step 3: STOP — confirm with the user before applying**

Present the drafted SQL and ask whether to apply it via `mcp__supabase__apply_migration`. Do not proceed past this point without an explicit go-ahead.

- [ ] **Step 4: Update `fetchUserReactionCounts(for:)`'s implementation**

Once the migration is applied, change the Supabase implementation to read the maintained aggregate instead of computing it live. No changes to `BoardService` protocol, `BoardStore+Profiles.swift`, or any UI.

- [ ] **Step 5: Run the full test suite and a manual Pop Score check**

Run: `xcodebuild test -scheme "On Board" -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5" -parallel-testing-enabled NO`
Expected: `** TEST SUCCEEDED **`. Manually confirm a profile's Pop Score in the live app still matches its actual reaction counts.

- [ ] **Step 6: Commit**

```bash
git add "On Board/Supabase/SupabaseBoardService+Profiles.swift"
git commit -m "Read denormalized Pop Score aggregate instead of computing it live"
```
