//
//  On_BoardTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct BoardWeekDecodingTests {
    @Test func missingBoardIdFailsInsteadOfSubstitutingDevBoard() {
        let json = """
        {"id":"\(UUID().uuidString)","startsAt":"2026-06-29T07:00:00Z","endsAt":"2026-07-06T07:00:00Z","status":"active"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(BoardWeek.self, from: Data(json.utf8))
        }
    }
}

@MainActor
struct BoardScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func clearingSoonWithinFinalThreeHours() {
        let sundayNight = date(year: 2025, month: 6, day: 15, hour: 21, minute: 30)
        #expect(BoardSchedule.isClearingSoon(from: sundayNight, calendar: calendar))
    }

    @Test func notClearingSoonOutsideFinalThreeHours() {
        let sundayMorning = date(year: 2025, month: 6, day: 15, hour: 6)
        #expect(!BoardSchedule.isClearingSoon(from: sundayMorning, calendar: calendar))
    }

    @Test func timeRemainingBreaksDownIntoDaysHoursMinutes() {
        let saturdayNight = date(year: 2025, month: 6, day: 14, hour: 21, minute: 30)
        let remaining = BoardSchedule.timeRemaining(from: saturdayNight, calendar: calendar)
        #expect(remaining.days == 1)
        #expect(remaining.hours == 2)
        #expect(remaining.minutes == 30)
    }
}

@MainActor
struct IntAbbreviatedTests {
    @Test func leavesSmallNumbersUnchanged() {
        #expect(999.abbreviated == "999")
    }

    @Test func abbreviatesThousands() {
        #expect(1_300.abbreviated == "1.3k")
    }
}

@MainActor
struct AppConfigurationTests {
    @Test func treatsEmptySupabaseValuesAsUnconfigured() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: "",
            googleClientID: ""
        )
        #expect(!config.isSupabaseConfigured)
        #expect(!config.isGoogleSignInConfigured)
    }

    @Test func detectsConfiguredSupabase() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon-key",
            googleClientID: "google-client-id"
        )
        #expect(config.isSupabaseConfigured)
        #expect(config.isGoogleSignInConfigured)
    }

    @Test func rejectsUnexpandedXcodePlaceholders() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://$(SUPABASE_URL)"),
            supabaseAnonKey: "$(SUPABASE_ANON_KEY)",
            googleClientID: "$(GOOGLE_CLIENT_ID)"
        )
        #expect(!config.isSupabaseConfigured)
        #expect(!config.isGoogleSignInConfigured)
    }

    @Test func loadRejectsPlaceholderStrings() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            googleClientID: nil
        )
        #expect(!config.isSupabaseConfigured)
    }
}

@MainActor
struct PhoneNumberNormalizerTests {
    @Test func formatsTenDigitUSNumbers() {
        #expect(PhoneNumberNormalizer.e164(from: "5555550100") == "+15555550100")
        #expect(PhoneNumberNormalizer.e164(from: "(555) 555-0100") == "+15555550100")
    }

    @Test func preservesExplicitCountryCode() {
        #expect(PhoneNumberNormalizer.e164(from: "+44 7911 123456") == "+447911123456")
    }

    @Test func rejectsTooShortNumbers() {
        #expect(PhoneNumberNormalizer.e164(from: "12345") == nil)
    }

    @Test func displayLabelFormatsUSNumbers() {
        #expect(PhoneNumberNormalizer.displayLabel(for: "+15555550100") == "(555) 555-0100")
    }
}

@MainActor
struct MockAuthServiceTests {
    @Test func signInPersistsAndRestoresSession() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthServiceTests")!
        defaults.removePersistentDomain(forName: "MockAuthServiceTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .apple)
        #expect(session.userId == SampleProfileID.maya)
        #expect(session.provider == .apple)
        #expect(session.hasLinked(.apple))

        let restored = try await service.restoreSession()
        #expect(restored == session)

        try await service.signOut()
        let cleared = try await service.restoreSession()
        #expect(cleared == nil)
    }

    @Test func googleSignInUsesDifferentSampleUser() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthServiceGoogleTests")!
        defaults.removePersistentDomain(forName: "MockAuthServiceGoogleTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .google)
        #expect(session.userId == SampleProfileID.leo)
        #expect(session.hasLinked(.google))
    }

    @Test func cannotUnlinkLastSignInMethod() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthUnlinkTests")!
        defaults.removePersistentDomain(forName: "MockAuthUnlinkTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .apple)
        let identity = try #require(session.linkedIdentities.first)

        do {
            _ = try await service.unlinkIdentity(id: identity.id)
            Issue.record("Expected cannotUnlinkLastSignInMethod")
        } catch let error as AuthError {
            #expect(error == .cannotUnlinkLastSignInMethod)
        }
    }

    @Test func canUnlinkWhenBackupMethodExists() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthUnlinkBackupTests")!
        defaults.removePersistentDomain(forName: "MockAuthUnlinkBackupTests")
        let service = MockAuthService(defaults: defaults)

        _ = try await service.signIn(with: .apple)
        _ = try await service.verifyLinkPhoneOTP(phone: "+15555550123", token: "123456")
        let session = try await service.restoreSession()
        let identity = try #require(session?.linkedIdentities.first)

        let updated = try await service.unlinkIdentity(id: identity.id)
        #expect(updated.linkedIdentities.isEmpty)
        #expect(updated.hasLinked(.phone))
    }
}

@MainActor
struct AuthSessionTests {
    @Test func countsSignInMethodsForUnlinkGuardrails() {
        let appleOnly = AuthSession(
            userId: UUID(),
            primaryProvider: .apple,
            linkedIdentities: [LinkedIdentity(id: "apple-1", provider: .apple, email: "you@icloud.com")]
        )
        #expect(!appleOnly.canUnlinkIdentity(appleOnly.linkedIdentities[0]))

        let phoneAndApple = AuthSession(
            userId: UUID(),
            primaryProvider: .phone,
            phone: "+15555550100",
            hasPhoneIdentity: true,
            linkedIdentities: [LinkedIdentity(id: "apple-1", provider: .apple, email: nil)]
        )
        #expect(phoneAndApple.canUnlinkIdentity(phoneAndApple.linkedIdentities[0]))
    }
}

struct AuthStoreTests {
    @Test @MainActor func signInUpdatesState() async {
        let defaults = UserDefaults(suiteName: "AuthStoreTests")!
        defaults.removePersistentDomain(forName: "AuthStoreTests")
        let auth = AuthStore(service: MockAuthService(defaults: defaults))

        await auth.signIn(with: .apple)
        #expect(auth.isSignedIn)
        #expect(auth.session?.userId == SampleProfileID.maya)
    }

    @Test @MainActor func signOutClearsState() async {
        let defaults = UserDefaults(suiteName: "AuthStoreSignOutTests")!
        defaults.removePersistentDomain(forName: "AuthStoreSignOutTests")
        let auth = AuthStore(service: MockAuthService(defaults: defaults))

        await auth.signIn(with: .apple)
        await auth.signOut()
        #expect(!auth.isSignedIn)
    }
}

private final class MockBoardService: BoardService, @unchecked Sendable {
    func listAccessibleBoards(for userID: UUID) async throws -> [Board] { throw BoardServiceError.notConfigured }
    func loadActiveBoard(boardID: UUID, for userID: UUID) async throws -> BoardSnapshot { throw BoardServiceError.notConfigured }
    func listArchivedWeeks(boardID: UUID, limit: Int, offset: Int) async throws -> [BoardWeek] { throw BoardServiceError.notConfigured }
    func fetchPosts(forWeek weekID: UUID, userID: UUID) async throws -> BoardWeekPosts { throw BoardServiceError.notConfigured }
    var commentsShouldFail = false
    func fetchComments(for postID: UUID) async throws -> CommentThread {
        if commentsShouldFail { throw BoardServiceError.notConfigured }
        return CommentThread(comments: [], userVotes: [:])
    }
    func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws {}
    func createPost(weekID: UUID, authorID: UUID, title: String, description: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post {
        Post(authorId: authorID, boardWeekId: weekID, title: title, description: description, author: "maya.c", tone: tone, imageUrl: imageUrl, imageAspectRatio: imageAspectRatio, tags: tags)
    }
    func updatePost(id: UUID, title: String, description: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { throw BoardServiceError.notConfigured }
    func deletePost(id: UUID) async throws {}
    func createComment(postID: UUID, authorID: UUID, authorHandle: String, body: String, parentCommentID: UUID?) async throws {}
    func updateComment(id: UUID, body: String) async throws {}
    func deleteComment(id: UUID) async throws {}
    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws {}
    func updateProfile(id: UUID, displayName: String, handle: String, bio: String?, avatarUrl: String?, birthday: String?, showBirthday: Bool?) async throws -> Profile { throw BoardServiceError.notConfigured }
    func checkHandleAvailable(_ handle: String) async throws -> Bool { true }
    func reportContent(targetType: ReportTargetType, targetID: UUID, reason: ReportReason, details: String?) async throws {}
    func blockUser(blockedID: UUID) async throws {}
    func unblockUser(blockedID: UUID) async throws {}
    func fetchBlockedUserIDs(for userID: UUID) async throws -> [UUID] { [] }
    func fetchProfiles(ids: [UUID]) async throws -> [Profile] { [] }
    func fetchNotificationSettings(for userID: UUID) async throws -> NotificationSettings { NotificationSettings() }
    var updateNotificationSettingsError: Error?
    // Lets a test hold the call in-flight so it can mutate store state before
    // the call resolves — without this, a synchronous test body never gives
    // the spawned Task a chance to actually be "in flight" when it matters.
    var updateNotificationSettingsDelay: Duration = .zero
    func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws {
        if updateNotificationSettingsDelay > .zero {
            try? await Task.sleep(for: updateNotificationSettingsDelay)
        }
        if let updateNotificationSettingsError { throw updateNotificationSettingsError }
    }
    var stubbedReactionCounts: [Reaction: Int] = [:]
    func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int] { stubbedReactionCounts }
    func followUser(id: UUID) async throws {}
    func unfollowUser(id: UUID) async throws {}
    func fetchFollowedUserIDs() async throws -> Set<UUID> { [] }
    func isFollowing(userID: UUID) async throws -> Bool { false }
    func searchTags(query: String) async throws -> [On_Board.Tag] { [] }
}

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
            title: "old",
            description: "week",
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
        let succeeded = await store.addPost(title: "hello", description: "world", tone: .blue)
        #expect(succeeded)
        #expect(store.posts.count == 1)
        #expect(store.posts[0].title == "hello")
        #expect(store.posts[0].author == "maya.c")
        #expect(store.posts[0].authorId == SampleProfileID.maya)
    }

    @Test @MainActor func setReactionUpdatesCounts() {
        let activeWeek = BoardWeek(
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let post = Post(title: "t", description: "d", author: "a", tone: .blue)
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
            authorId: profile.id,
            boardWeekId: week.id,
            title: "cached",
            description: "d",
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
            boardId: boardID,
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
            title: "cached",
            description: "d",
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
        let reader = BoardStore()
        reader.hydrateFromDiskIfNeeded(boardID: boardID)
        #expect(reader.popScore(for: profile.id)?[.like] == 5)
    }

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
}

@MainActor
struct NetworkErrorClassifierTests {
    @Test func zeroByteResourceIsConnectivityFailure() {
        #expect(NetworkErrorClassifier.isConnectivityFailure(URLError(.zeroByteResource)))
    }

    @Test func notConnectedToInternetIsConnectivityFailure() {
        #expect(NetworkErrorClassifier.isConnectivityFailure(URLError(.notConnectedToInternet)))
    }

    @Test func badServerResponseIsNotConnectivityFailure() {
        #expect(!NetworkErrorClassifier.isConnectivityFailure(URLError(.badServerResponse)))
    }
}

@MainActor
struct ProfileIndexTests {
    @Test func looksUpByHandleCaseInsensitively() {
        let index = ProfileIndex(profiles: Profile.samples)
        #expect(index.profile(handle: "MAYA.C")?.id == SampleProfileID.maya)
        #expect(index.profile(id: SampleProfileID.leo)?.handle == "leokp")
    }
}

@MainActor
struct CommentTreeBuilderTests {
    @Test func buildsNestedReplies() {
        let rootID = UUID()
        let replyID = UUID()
        let flat: [CommentTreeBuilder.FlatComment] = [
            .init(
                id: rootID,
                authorId: SampleProfileID.maya,
                authorHandle: "maya.c",
                body: "root",
                parentCommentId: nil,
                likeCount: 2,
                dislikeCount: 0,
                createdAt: .now
            ),
            .init(
                id: replyID,
                authorId: SampleProfileID.leo,
                authorHandle: "leokp",
                body: "reply",
                parentCommentId: rootID,
                likeCount: 0,
                dislikeCount: 1,
                createdAt: .now.addingTimeInterval(1)
            )
        ]

        let tree = CommentTreeBuilder.buildTree(from: flat)
        #expect(tree.count == 1)
        #expect(tree[0].replies.count == 1)
        #expect(tree[0].replies[0].body == "reply")
    }
}

@MainActor
struct RemotePostRowTests {
    @Test func decodesPostsWithMetaShape() throws {
        let json = """
        {
          "id": "A0000000-0000-4000-8000-000000000099",
          "board_week_id": "B0000000-0000-4000-8000-000000000001",
          "author_id": "A0000000-0000-4000-8000-000000000001",
          "author": "maya.c",
          "title": "Hello",
          "description": "World",
          "tone": "blue",
          "created_at": "2026-06-15T12:00:00Z",
          "is_read_only": false,
          "reaction_counts": { "like": 3 }
        }
        """.data(using: .utf8)!

        let row = try BoardJSON.decoder.decode(RemotePostRow.self, from: json)
        #expect(row.author == "maya.c")
        #expect(row.reactionCounts[.like] == 3)
        #expect(row.toPost().isReadOnly == false)
    }

    @Test func mergesLegacyLoveCountsIntoLike() throws {
        let json = """
        {
          "id": "A0000000-0000-4000-8000-000000000099",
          "board_week_id": "B0000000-0000-4000-8000-000000000001",
          "author_id": "A0000000-0000-4000-8000-000000000001",
          "author": "maya.c",
          "title": "Hello",
          "description": "World",
          "tone": "blue",
          "created_at": "2026-06-15T12:00:00Z",
          "is_read_only": false,
          "reaction_counts": { "like": 2, "love": 1 }
        }
        """.data(using: .utf8)!

        let row = try BoardJSON.decoder.decode(RemotePostRow.self, from: json)
        #expect(row.reactionCounts[.like] == 3)
        #expect(row.reactionCounts.count == 1)
    }
}

@MainActor
struct SupabaseClientFactoryTests {
    @Test func returnsNilWhenUnconfigured() {
        let config = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            googleClientID: nil
        )
        #expect(SupabaseClientFactory.client(for: config) == nil)
    }

    @Test func returnsSharedClientForSameConfiguration() {
        let config = AppConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "test-key",
            googleClientID: nil
        )
        let first = SupabaseClientFactory.client(for: config)
        let second = SupabaseClientFactory.client(for: config)
        #expect(first != nil)
        #expect(first === second)
    }
}

@MainActor
struct SupabaseAuthServiceTests {
    @Test func throwsWhenSupabaseIsNotConfigured() async {
        let service = SupabaseAuthService(
            configuration: AppConfiguration(
                supabaseURL: nil,
                supabaseAnonKey: nil,
                googleClientID: nil
            )
        )

        do {
            _ = try await service.signIn(with: .apple)
            Issue.record("Expected notConfigured error")
        } catch let error as AuthError {
            #expect(error == .notConfigured)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@MainActor
struct HandleRulesTests {
    @Test func acceptsValidHandles() {
        #expect(HandleRules.isValid("maya.c"))
        #expect(HandleRules.isValid("leo_kp"))
        #expect(HandleRules.isValid("ab"))
    }

    @Test func rejectsInvalidHandles() {
        #expect(!HandleRules.isValid("a"))
        #expect(!HandleRules.isValid("has spaces"))
        #expect(!HandleRules.isValid("bad@handle"))
    }

    @Test func detectsProvisionalHandles() {
        #expect(HandleRules.isProvisional("u_abc123"))
        #expect(!HandleRules.isProvisional("maya.c"))
    }
}

@MainActor
struct MockOnboardingServiceTests {
    @Test func phoneUserStartsAtBirthday() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingPhone")!
        defaults.removePersistentDomain(forName: "MockOnboardingPhone")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550100", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        let status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .birthday)
        #expect(status.isComplete == false)
    }

    @Test func completesOnboardingFlow() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingFlow")!
        defaults.removePersistentDomain(forName: "MockOnboardingFlow")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550101", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        _ = try await onboarding.completeUsername("new.tester")
        var status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .profile)

        _ = try await onboarding.completeProfile(displayName: "New Tester", bio: "Hello", avatarUrl: nil)
        status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .schoolVerify)

        _ = try await onboarding.beginSchoolEmailVerification("student@example.edu")
        _ = try await onboarding.completeSchoolEmailVerification("student@example.edu", token: "123456")
        status = try await onboarding.fetchStatus()
        // Verifying the .edu is what places the user on the waitlist — there is no
        // separate "join" tap. They stay parked (on the waitlist, not complete)
        // until an admin admits them and assigns a board.
        #expect(status.onboardingStep == .waitlist)
        #expect(status.isComplete == false)
        #expect(status.waitlistJoinedAt != nil)
    }
}

@MainActor
struct SchoolEmailRulesTests {
    @Test func acceptsEduAddresses() {
        #expect(SchoolEmailRules.isValid("student@example.edu"))
    }

    @Test func rejectsNonEduAddresses() {
        #expect(!SchoolEmailRules.isValid("student@gmail.com"))
    }
}

struct OnboardingStoreTests {
    @Test @MainActor func refreshMarksCompleteForSampleAppleUser() async {
        let authDefaults = UserDefaults(suiteName: "OnboardingStoreAppleAuth")!
        authDefaults.removePersistentDomain(forName: "OnboardingStoreAppleAuth")
        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        await auth.signIn(with: .apple)

        let store = OnboardingStore(
            service: MockOnboardingService(defaults: authDefaults),
            auth: auth,
            network: NetworkMonitor()
        )
        await store.refresh()
        #expect(store.isComplete)
        #expect(!store.needsOnboarding)
    }

    @Test @MainActor func provisionalCompleteProfileStillNeedsOnboarding() {
        let status = OnboardingStatus(
            id: UUID(),
            handle: "u_abc123def456",
            displayName: "",
            bio: nil,
            avatarUrl: nil,
            birthday: "2000-01-01",
            showBirthday: false,
            onboardingStep: .complete,
            onboardingCompletedAt: .now,
            waitlistJoinedAt: nil,
            verifiedSchoolEmail: nil,
            pendingSchoolEmail: nil,
            schoolName: nil,
            boardId: nil,
            boardName: nil
        )

        #expect(status.isComplete)
        #expect(status.needsOnboarding)
        #expect(status.effectiveOnboardingStep == .username)
    }
}

@MainActor
struct OnboardingStalenessTests {
    /// Wraps `MockOnboardingService` to count `fetchStatus()` calls, so the test
    /// can assert `refreshIfOnline()` only refetches once the cached status is stale.
    private final class CountingOnboardingService: OnboardingService, @unchecked Sendable {
        let inner: MockOnboardingService
        nonisolated(unsafe) var fetchCount = 0

        init(defaults: UserDefaults) {
            inner = MockOnboardingService(defaults: defaults)
        }

        func fetchStatus() async throws -> OnboardingStatus {
            fetchCount += 1
            return try await inner.fetchStatus()
        }

        func completeBirthday(birthday: Date, showBirthday: Bool) async throws -> OnboardingStep {
            try await inner.completeBirthday(birthday: birthday, showBirthday: showBirthday)
        }

        func checkHandleAvailable(_ handle: String) async throws -> Bool {
            try await inner.checkHandleAvailable(handle)
        }

        func completeUsername(_ handle: String) async throws -> OnboardingStep {
            try await inner.completeUsername(handle)
        }

        func completeProfile(displayName: String, bio: String?, avatarUrl: String?) async throws -> OnboardingStep {
            try await inner.completeProfile(displayName: displayName, bio: bio, avatarUrl: avatarUrl)
        }

        func lookupSchool(for email: String) async throws -> SchoolMatch? {
            try await inner.lookupSchool(for: email)
        }

        func beginSchoolEmailVerification(_ email: String) async throws -> SchoolMatch {
            try await inner.beginSchoolEmailVerification(email)
        }

        func completeSchoolEmailVerification(_ email: String, token: String) async throws -> OnboardingStep {
            try await inner.completeSchoolEmailVerification(email, token: token)
        }

        func joinWaitlist() async throws -> OnboardingStep {
            try await inner.joinWaitlist()
        }
    }

    @Test func refreshIfOnlineRefetchesOnceStatusIsStale() async throws {
        let authDefaults = UserDefaults(suiteName: "OnboardingStalenessAuth")!
        authDefaults.removePersistentDomain(forName: "OnboardingStalenessAuth")

        let auth = AuthStore(service: MockAuthService(defaults: authDefaults))
        await auth.signIn(with: .apple)

        let service = CountingOnboardingService(defaults: authDefaults)
        let store = OnboardingStore(service: service, auth: auth, network: NetworkMonitor())

        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Fresh: no refetch.
        await store.refreshIfOnline()
        #expect(service.fetchCount == 1)

        // Stale: refetch.
        store.statusStaleInterval = 0
        await store.refreshIfOnline()
        #expect(service.fetchCount == 2)
    }
}

@MainActor
struct OnboardingCoordinatorTargetPathTests {
    // A returning, already-onboarded user must not be routed into any onboarding
    // step screen — the coordinator gets swapped out for BoardListView instead.
    @Test func completeStepProducesEmptyPath() {
        #expect(OnboardingCoordinator.targetPath(for: .complete, isSignedIn: true) == [])
    }

    @Test func usernameStepProducesUsernamePath() {
        #expect(OnboardingCoordinator.targetPath(for: .username, isSignedIn: true) == [.birthday, .username])
    }

    @Test func waitlistStepProducesFullPath() {
        #expect(
            OnboardingCoordinator.targetPath(for: .waitlist, isSignedIn: true)
                == [.birthday, .username, .profile, .contentPreferences, .schoolVerify, .waitlist]
        )
    }

    @Test func signedOutProducesEmptyPathRegardlessOfStep() {
        #expect(OnboardingCoordinator.targetPath(for: .waitlist, isSignedIn: false) == [])
    }
}

@MainActor
struct SignInMethodCountingTests {
    private func session(
        email: String? = nil,
        phone: String? = nil,
        hasEmailIdentity: Bool = false,
        hasPhoneIdentity: Bool = false,
        identities: [LinkedIdentity] = []
    ) -> AuthSession {
        AuthSession(
            userId: UUID(),
            primaryProvider: .google,
            email: email,
            phone: phone,
            hasEmailIdentity: hasEmailIdentity,
            hasPhoneIdentity: hasPhoneIdentity,
            linkedIdentities: identities
        )
    }

    // A Google-only user has user.email copied from the OAuth provider.
    // That copied email must NOT count as a sign-in method.
    @Test func oauthCopiedEmailDoesNotAllowUnlinkingSoleIdentity() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", identities: [google])
        #expect(!s.canUnlinkIdentity(google))
        #expect(s.remainingSignInMethodCount(excludingIdentityId: "g1") == 0)
    }

    @Test func realEmailIdentityAllowsUnlinkingOAuth() {
        let google = LinkedIdentity(id: "g1", provider: .google, email: "me@gmail.com")
        let s = session(email: "me@gmail.com", hasEmailIdentity: true, identities: [google])
        #expect(s.canUnlinkIdentity(google))
    }

    @Test func hasLinkedUsesIdentityFlagsNotCopiedFields() {
        let s = session(email: "me@gmail.com", phone: "+15555550100")
        #expect(!s.hasLinked(.email))
        #expect(!s.hasLinked(.phone))
        let s2 = session(hasEmailIdentity: true, hasPhoneIdentity: true)
        #expect(s2.hasLinked(.email))
        #expect(s2.hasLinked(.phone))
    }

    @Test func decodingOldSessionWithoutFlagsDefaultsToFalse() throws {
        let json = """
        {"userId":"\(UUID().uuidString)","primaryProvider":"google","email":"a@b.co","linkedIdentities":[]}
        """
        let decoded = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))
        #expect(!decoded.hasEmailIdentity)
        #expect(!decoded.hasPhoneIdentity)
    }
}

struct AppleNameAdoptionTests {
    @Test func adoptsWhenCurrentNameEmpty() {
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: ""))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: "   "))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: nil))
    }

    @Test func neverOverwritesAChosenName() {
        #expect(!AppleNameAdoption.shouldAdopt(currentDisplayName: "Jawad Khadra"))
    }
}

/// AuthService stub whose restore/sign-out behavior is scripted per test.
/// Every other requirement is unreachable in these tests.
private final class ScriptedAuthService: AuthService, @unchecked Sendable {
    var restoreResult: Result<AuthSession?, Error> = .success(nil)
    var signOutError: Error?

    func restoreSession() async throws -> AuthSession? { try restoreResult.get() }
    func signOut() async throws { if let signOutError { throw signOutError } }

    func signIn(with provider: AuthProvider) async throws -> AuthSession { fatalError("unused") }
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession { fatalError("unused") }
    func signInWithGoogle() async throws -> AuthSession { fatalError("unused") }
    func sendPhoneOTP(phone: String) async throws { fatalError("unused") }
    func verifyPhoneOTP(phone: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func sendEmailOTP(email: String) async throws { fatalError("unused") }
    func verifyEmailOTP(email: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func signInWithPassword(email: String, password: String) async throws -> AuthSession { fatalError("unused") }
    func signUpWithPassword(email: String, password: String) async throws -> AuthSession? { fatalError("unused") }
    func checkEmailExists(email: String) async throws -> EmailStatus { fatalError("unused") }
    func setPassword(_ password: String) async throws -> AuthSession { fatalError("unused") }
    func linkApple(idToken: String, nonce: String?) async throws -> AuthSession { fatalError("unused") }
    func linkGoogle() async throws -> AuthSession { fatalError("unused") }
    func sendLinkPhoneOTP(phone: String) async throws { fatalError("unused") }
    func verifyLinkPhoneOTP(phone: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func sendLinkEmailOTP(email: String) async throws { fatalError("unused") }
    func verifyLinkEmailOTP(email: String, token: String) async throws -> AuthSession { fatalError("unused") }
    func unlinkIdentity(id: String) async throws -> AuthSession { fatalError("unused") }
    func refreshAuthSession() async throws -> AuthSession? { nil }
    func deleteAccount() async throws { fatalError("unused") }
    func revokeApple(authorizationCode: String) async throws { fatalError("unused") }
}

@MainActor
struct AuthRestoreOfflineTests {
    @Test func connectivityFailureDuringRestoreBecomesRestoreFailedOffline() async {
        let service = ScriptedAuthService()
        service.restoreResult = .failure(AuthError.networkUnavailable)
        let store = AuthStore(service: service)
        await store.restoreSession()
        #expect(store.state == .restoreFailedOffline)
        #expect(!store.isSignedIn)
    }

    @Test func signOutErrorStillSignsOutLocally() async {
        let service = ScriptedAuthService()
        service.signOutError = AuthError.networkUnavailable
        let store = AuthStore(service: service)
        await store.signOut()
        #expect(store.state == .signedOut)
    }
}

@MainActor
struct BoardSwitchRaceTests {
    /// BoardService stub whose loadActiveBoard for a chosen board suspends until released.
    final class SlowBoardService: BoardService, @unchecked Sendable {
        var slowBoardID: UUID?
        private var continuation: CheckedContinuation<Void, Never>?

        func releaseSlowLoad() {
            continuation?.resume()
            continuation = nil
        }

        func loadActiveBoard(boardID: UUID, for userID: UUID) async throws -> BoardSnapshot {
            if boardID == slowBoardID {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { self.continuation = $0 }
                } onCancel: {
                    Task { @MainActor in self.releaseSlowLoad() }
                }
            }
            let week = BoardWeek(
                boardId: boardID,
                startsAt: .now,
                endsAt: .now.addingTimeInterval(604_800),
                status: .active
            )
            return BoardSnapshot(week: week, posts: [], profiles: [], userReactions: [:])
        }

        func listArchivedWeeks(boardID: UUID, limit: Int, offset: Int) async throws -> [BoardWeek] { [] }
        func listAccessibleBoards(for userID: UUID) async throws -> [Board] { [] }
        func fetchPosts(forWeek weekID: UUID, userID: UUID) async throws -> BoardWeekPosts { fatalError("unused") }
        func fetchComments(for postID: UUID) async throws -> CommentThread { fatalError("unused") }
        func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws { fatalError("unused") }
        func createPost(weekID: UUID, authorID: UUID, title: String, description: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { fatalError("unused") }
        func updatePost(id: UUID, title: String, description: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { fatalError("unused") }
        func deletePost(id: UUID) async throws { fatalError("unused") }
        func createComment(postID: UUID, authorID: UUID, authorHandle: String, body: String, parentCommentID: UUID?) async throws { fatalError("unused") }
        func updateComment(id: UUID, body: String) async throws { fatalError("unused") }
        func deleteComment(id: UUID) async throws { fatalError("unused") }
        func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws { fatalError("unused") }
        func updateProfile(id: UUID, displayName: String, handle: String, bio: String?, avatarUrl: String?, birthday: String?, showBirthday: Bool?) async throws -> Profile { fatalError("unused") }
        func checkHandleAvailable(_ handle: String) async throws -> Bool { fatalError("unused") }
        func reportContent(targetType: ReportTargetType, targetID: UUID, reason: ReportReason, details: String?) async throws { fatalError("unused") }
        func blockUser(blockedID: UUID) async throws { fatalError("unused") }
        func unblockUser(blockedID: UUID) async throws { fatalError("unused") }
        // refresh() fetches blocked IDs after every snapshot — must not trap.
        func fetchBlockedUserIDs(for userID: UUID) async throws -> [UUID] { [] }
        func fetchProfiles(ids: [UUID]) async throws -> [Profile] { [] }
        func fetchNotificationSettings(for userID: UUID) async throws -> NotificationSettings { NotificationSettings() }
        func updateNotificationSettings(_ settings: NotificationSettings, for userID: UUID) async throws { fatalError("unused") }
        func fetchUserReactionCounts(for userID: UUID) async throws -> [Reaction: Int] { [:] }
        func followUser(id: UUID) async throws { fatalError("unused") }
        func unfollowUser(id: UUID) async throws { fatalError("unused") }
        // refresh() fetches followed IDs after every snapshot — must not trap.
        func fetchFollowedUserIDs() async throws -> Set<UUID> { [] }
    func isFollowing(userID: UUID) async throws -> Bool { false }
        func searchTags(query: String) async throws -> [On_Board.Tag] { fatalError("unused") }
    }

    @Test func switchingBoardsMidLoadLoadsTheNewBoard() async {
        let boardA = UUID(), boardB = UUID(), user = UUID()
        let service = SlowBoardService()
        service.slowBoardID = boardA
        let store = BoardStore(boardService: service)
        store.setBoard(id: boardA, name: "A")

        let firstLoad = Task { await store.refresh(for: user) }
        await Task.yield()  // let the slow load start and suspend

        store.setBoard(id: boardB, name: "B")
        await store.refresh(for: user)

        service.releaseSlowLoad()
        await firstLoad.value

        #expect(store.currentBoardId == boardB)
        #expect(store.activeBoardWeek?.boardId == boardB)
    }
}

@MainActor
struct NotificationSettingsTests {
    @Test func decodesFromJSONWithSnakeCase() throws {
        let json = """
        {
          "push_reactions": true,
          "push_comments": false,
          "push_new_posts": true
        }
        """.data(using: .utf8)!
        
        let settings = try BoardJSON.decoder.decode(NotificationSettings.self, from: json)
        #expect(settings.pushReactions == true)
        #expect(settings.pushComments == false)
        #expect(settings.pushNewPosts == true)
    }

    @Test func providesDefaultValues() {
        let settings = NotificationSettings()
        #expect(settings.pushReactions == true)
        #expect(settings.pushComments == true)
        #expect(settings.pushNewPosts == true)
    }
}

/// `follows` rows round-trip through `BoardJSON`, whose `.convertFromSnakeCase`
/// strategy camel-cases incoming keys before matching them. A `CodingKeys` entry
/// spelling out `"following_id"` therefore breaks decoding while leaving encoding
/// intact — follows write to the DB but never read back, so the Follow button
/// never flips to "Following". These pin both directions.
@MainActor
struct FollowRowCodingTests {
    @Test func decodesSnakeCaseFollowingIDFromPostgREST() throws {
        let id = UUID()
        let json = #"[{"following_id":"\#(id.uuidString)"}]"#.data(using: .utf8)!

        let rows = try BoardJSON.decoder.decode([SupabaseBoardService.FollowRow].self, from: json)

        #expect(rows.count == 1)
        #expect(rows.first?.followingId == id)
    }

    @Test func encodesFollowingIDAsSnakeCaseForPostgREST() throws {
        let id = UUID()

        let data = try BoardJSON.encoder.encode(SupabaseBoardService.FollowRow(followingId: id))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object.keys.contains("following_id"))
        #expect(object["following_id"] as? String == id.uuidString)
    }
}

/// `fetch_tags_for_week` returns `(post_id, tag_name)`. Same `.convertFromSnakeCase`
/// trap as `FollowRow` — and the only caller swallows the throw with `try?`, so a
/// regression here makes every post's tags silently disappear rather than erroring.
@MainActor
struct TagRowCodingTests {
    @Test func decodesSnakeCaseTagRowFromPostgREST() throws {
        let postID = UUID()
        let json = #"[{"post_id":"\#(postID.uuidString)","tag_name":"testing"}]"#.data(using: .utf8)!

        let rows = try BoardJSON.decoder.decode([SupabaseBoardService.TagRow].self, from: json)

        #expect(rows.count == 1)
        #expect(rows.first?.postId == postID)
        #expect(rows.first?.tagName == "testing")
    }
}

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
            authorId: profile.id,
            boardWeekId: week.id,
            title: "cached post",
            description: "d",
            author: profile.handle
        )
        let envelope = CacheEnvelope(
            schemaVersion: CacheEnvelope.currentSchemaVersion,
            cachedAt: .now,
            boardId: boardID,
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
        #expect(decoded.boardId == boardID)
        #expect(decoded.snapshot.week.id == week.id)
        #expect(decoded.snapshot.posts.first?.id == post.id)
        #expect(decoded.popScores[profile.id]?[.like] == 3)
        #expect(decoded.notificationSettings?.pushComments == false)
    }
}

/// The `user_settings` upsert body must carry *every* stored column. `pushFollowedPosts`
/// was absent, so toggling "People You Follow" appeared to work and then reverted.
@MainActor
struct NotificationSettingsPayloadTests {
    @Test func encodesEveryStoredColumnAsSnakeCase() throws {
        let userID = UUID()
        let settings = NotificationSettings(
            pushReactions: true,
            pushComments: false,
            pushNewPosts: true,
            pushFollowedPosts: false
        )

        let data = try BoardJSON.encoder.encode(
            SupabaseBoardService.NotificationSettingsPayload(userID: userID, settings: settings)
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["user_id"] as? String == userID.uuidString)
        #expect(object["push_reactions"] as? Bool == true)
        #expect(object["push_comments"] as? Bool == false)
        #expect(object["push_new_posts"] as? Bool == true)
        // The regression: this key used to be missing entirely.
        #expect(object["push_followed_posts"] as? Bool == false)
    }
}
