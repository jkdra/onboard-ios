//
//  BoardStoreTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct BoardStoreTests {
    @Test @MainActor func archivedWeekPostsAreReadOnly() {
        let activeWeek = BoardWeek(
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let archivedWeek = BoardWeek(
            startsAt: .now.addingTimeInterval(-86_400 * 14),
            endsAt: .now.addingTimeInterval(-86_400 * 7),
            status: .archived,
            archivedAt: .now.addingTimeInterval(-86_400 * 7)
        )
        let archivedPost = Post(
            boardWeekId: archivedWeek.id,
            isReadOnly: true,
            content: "old week",
            author: "maya.c"
        )
        let store = BoardStore(
            posts: [archivedPost],
            profiles: Profile.samples,
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardWeeks: [archivedWeek, activeWeek],
            currentBoard: Board(id: archivedWeek.boardId, name: "Test")
        )

        #expect(!store.canInteract(with: archivedWeek))
        #expect(store.canInteractWithBoard)
        #expect(!store.canInteract(with: archivedPost))
        store.setReaction(postId: archivedPost.id, reaction: .like)
        #expect(store.userReaction(for: archivedPost.id) == nil)
    }

    @Test @MainActor func addPostInsertsAtTop() async {
        let activeWeek = BoardWeek(
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let store = BoardStore(
            posts: [],
            profiles: [Profile.samples[0]],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: MockBoardService()
        )
        let succeeded = await store.addPost(content: "hello world", tone: .blue)
        #expect(succeeded)
        #expect(store.posts.count == 1)
        #expect(store.posts[0].content == "hello world")
        #expect(store.posts[0].author == "maya.c")
        #expect(store.posts[0].authorId == SampleProfileID.maya)
    }

    @Test @MainActor func setReactionUpdatesCounts() {
        let activeWeek = BoardWeek(
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let post = Post(content: "t d", author: "a", tone: .blue)
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek
        )
        store.setReaction(postId: post.id, reaction: .like)
        #expect(store.post(with: post.id)?.reactionCounts[.like] == 1)
        store.setReaction(postId: post.id, reaction: nil)
        #expect(store.post(with: post.id)?.reactionCounts[.like] == 0)
    }

    @Test @MainActor func ownershipChecksUseStableProfileIDs() {
        let mayaPost = Post.samples.first { $0.author == "maya.c" }!
        let leoPost = Post.samples.first { $0.author == "leokp" }!
        let store = BoardStore.sampleBoard(currentUserID: SampleProfileID.maya)

        #expect(store.canEdit(post: mayaPost))
        #expect(!store.canEdit(post: leoPost))
    }

    @Test @MainActor func commentOwnershipFallsBackToHandle() {
        let comment = Comment.authored(by: "maya.c", body: "test")
        let store = BoardStore.sampleBoard(currentUserID: SampleProfileID.maya)
        #expect(store.canEdit(comment: comment))
    }

    @Test @MainActor func profileLookupBuildsFallbackForUnknownHandle() {
        let store = BoardStore.sampleBoard()
        let profile = store.profile(forAuthor: "unknown.user")
        #expect(profile.handle == "unknown.user")
    }

    // A weak/dropped connection can make PostgREST's response arrive as zero bytes,
    // which URLSession surfaces as .zeroByteResource rather than a decoding error.
    // This should read as a connectivity failure, not leak a raw system error string.
    @Test @MainActor func mapLoadErrorTreatsZeroByteResourceAsNetworkUnavailable() {
        let error = URLError(.zeroByteResource)
        #expect(BoardStore.mapLoadError(error) == AuthError.networkUnavailable.localizedDescription)
    }

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
        // Keep the first save's network call in flight long enough that we can
        // mutate state out from under it before it resolves.
        service.updateNotificationSettingsDelay = .milliseconds(100)

        // First save: optimistic mutation happens synchronously, then the sync
        // Task suspends inside the mock's artificial delay — it has not yet
        // reached (or thrown from) `updateNotificationSettings`.
        store.setNotificationSettings(NotificationSettings(pushComments: false, pushNewPosts: true))

        // Give the spawned Task a real chance to start running and enter the
        // mock's sleep, so it is genuinely "in flight" (not merely scheduled)
        // when we supersede it below. This gap is well under the 100ms delay.
        try await Task.sleep(for: .milliseconds(10))

        // Simulate a newer value arriving via some path OTHER than
        // setNotificationSettings (e.g. an external revalidation/refresh) —
        // this does NOT cancel the first task's `notificationSettingsSyncTask`,
        // so when the first call's failure is finally caught, it reaches the
        // `guard notificationSettings == newSettings else { return }` stale
        // check rather than short-circuiting on `Task.isCancelled`.
        store.notificationSettings = NotificationSettings(pushComments: false, pushNewPosts: false)

        // Let the first save's delayed network call finish and throw.
        try await Task.sleep(for: .milliseconds(150))

        // The first save's rollback must not clobber the newer value that
        // arrived while it was still in flight.
        #expect(store.notificationSettings?.pushNewPosts == false)
    }
}

extension BoardStoreTests {
    @Test @MainActor func hydrateFromDiskRestoresWarmState() async {
        let boardID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let profile = Profile.samples[0]
        let post = Post(
            authorId: profile.id,
            boardWeekId: week.id,
            content: "cached d",
            author: profile.handle
        )
        let writer = BoardStore(
            posts: [post],
            profiles: [profile],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test")
        )
        writer.persistToDisk()
        // The writer coalesces off-main now — land the write before reading.
        await writer.flushCacheWrites()
        defer { writer.clearDiskCache() }

        let reader = BoardStore()
        await reader.hydrateFromDiskIfNeeded(boardID: boardID)

        #expect(reader.activeBoardWeek?.boardId == boardID)
        #expect(reader.posts.contains { $0.id == post.id })
        #expect(reader.profile(id: profile.id)?.id == profile.id)
    }

    @Test @MainActor func mismatchedSchemaVersionIsTreatedAsMiss() async throws {
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
            boardId: boardID,
            snapshot: BoardSnapshot(week: week, posts: [], profiles: [], userReactions: [:]),
            archivedWeeks: [],
            popScores: [:],
            toneCounts: nil,
            comments: [:],
            commentVotes: [:],
            notificationSettings: nil
        )
        let data = try BoardJSON.encoder.encode(staleEnvelope)
        try data.write(to: BoardStore.cacheFileURL, options: .atomic)

        let reader = BoardStore()
        await reader.hydrateFromDiskIfNeeded(boardID: boardID)

        #expect(reader.activeBoardWeek == nil)
        #expect(!FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))
    }

    @Test @MainActor func clearDiskCacheRemovesFile() async {
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
        await store.flushCacheWrites()
        #expect(FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))

        // Everything is flushed, so clear's synchronous first delete is the
        // one that acts here — the assertion doesn't race the async pass.
        store.clearDiskCache()
        #expect(!FileManager.default.fileExists(atPath: BoardStore.cacheFileURL.path))
    }

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
            authorId: profile.id,
            boardWeekId: week.id,
            content: "cached d",
            author: profile.handle
        )
        let writer = BoardStore(
            posts: [post],
            profiles: [profile],
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test")
        )
        writer.persistToDisk()
        await writer.flushCacheWrites()
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
        await store.flushCacheWrites()
        let reader = BoardStore()
        await reader.hydrateFromDiskIfNeeded(boardID: boardID)
        #expect(reader.popScore(for: profile.id)?[.like] == 5)
    }

    @Test @MainActor func loadCommentsRevalidationFailsSilentlyWhenAlreadyWarm() async {
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let post = Post(boardWeekId: activeWeek.id, content: "t d", author: "maya.c", comments: [.authored(by: "maya.c", body: "hi")])
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
        let post = Post(boardWeekId: activeWeek.id, content: "t d", author: "maya.c")
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

    // Moderation (block/report) had zero coverage — the optimistic-mutate,
    // rollback-on-failure shape here mirrors setReaction/setNotificationSettings,
    // but nothing previously pinned it for block/unblock/report.
    @Test @MainActor func blockUserRemovesContentAndPersistsTheBlock() async throws {
        let blockedAuthor = SampleProfileID.leo
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let blockedPost = Post(authorId: blockedAuthor, boardWeekId: activeWeek.id, content: "t d", author: "leokp")
        let store = BoardStore(
            posts: [blockedPost],
            profiles: Profile.samples,
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: MockBoardService()
        )

        try await store.block(userID: blockedAuthor)

        #expect(store.isBlocked(userID: blockedAuthor))
        #expect(store.posts.isEmpty)
    }

    @Test @MainActor func blockUserRollsBackContentAndBlockedSetOnFailure() async throws {
        let blockedAuthor = SampleProfileID.leo
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let blockedPost = Post(authorId: blockedAuthor, boardWeekId: activeWeek.id, content: "t d", author: "leokp")
        let service = MockBoardService()
        service.blockUserError = BoardServiceError.notConfigured
        let store = BoardStore(
            posts: [blockedPost],
            profiles: Profile.samples,
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: service
        )

        await #expect(throws: (any Error).self) {
            try await store.block(userID: blockedAuthor)
        }

        #expect(!store.isBlocked(userID: blockedAuthor))
        #expect(store.posts.count == 1)
    }

    @Test @MainActor func unblockUserRollsBackOnFailure() async throws {
        let blockedAuthor = SampleProfileID.leo
        let service = MockBoardService()
        service.unblockUserError = BoardServiceError.notConfigured
        let store = BoardStore(
            posts: [],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            boardService: service
        )
        store.blockedUserIDs = [blockedAuthor]

        await #expect(throws: (any Error).self) {
            try await store.unblock(userID: blockedAuthor)
        }

        #expect(store.isBlocked(userID: blockedAuthor))
    }

    @Test @MainActor func reportingAPostRemovesItLocally() async throws {
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let post = Post(boardWeekId: activeWeek.id, content: "t d", author: "maya.c")
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: MockBoardService()
        )

        try await store.report(post: post, reason: .spam, details: nil)

        #expect(store.posts.isEmpty)
    }

    @Test @MainActor func reportingAPostPropagatesFailureWithoutRemovingIt() async throws {
        let activeWeek = BoardWeek(startsAt: .now, endsAt: .now.addingTimeInterval(86_400 * 7), status: .active)
        let post = Post(boardWeekId: activeWeek.id, content: "t d", author: "maya.c")
        let service = MockBoardService()
        service.reportContentError = BoardServiceError.notConfigured
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek,
            boardService: service
        )

        await #expect(throws: (any Error).self) {
            try await store.report(post: post, reason: .spam, details: nil)
        }

        #expect(store.posts.count == 1)
    }
}
