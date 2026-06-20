//
//  On_BoardTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct BoardScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func clearingSoonWithinFinalTwelveHours() {
        let sundayEvening = date(year: 2025, month: 6, day: 15, hour: 18)
        #expect(BoardSchedule.isClearingSoon(from: sundayEvening, calendar: calendar))
    }

    @Test func notClearingSoonOutsideFinalTwelveHours() {
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

struct IntAbbreviatedTests {
    @Test func leavesSmallNumbersUnchanged() {
        #expect(999.abbreviated == "999")
    }

    @Test func abbreviatesThousands() {
        #expect(1_300.abbreviated == "1.3k")
    }
}

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

struct MockAuthServiceTests {
    @Test func signInPersistsAndRestoresSession() async throws {
        let defaults = UserDefaults(suiteName: "MockAuthServiceTests")!
        defaults.removePersistentDomain(forName: "MockAuthServiceTests")
        let service = MockAuthService(defaults: defaults)

        let session = try await service.signIn(with: .apple)
        #expect(session.userId == SampleProfileID.maya)
        #expect(session.provider == .apple)

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
            activeBoardWeek: activeWeek
        )
        await store.addPost(title: "hello", description: "world", tone: .blue)
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

    @Test @MainActor func remoteReactionChangeUpdatesCountsFromOtherUsers() {
        let activeWeek = BoardWeek(
            startsAt: .now,
            endsAt: .now.addingTimeInterval(86_400 * 7),
            status: .active
        )
        let post = Post(
            title: "t",
            description: "d",
            author: "a",
            tone: .blue,
            reactionCounts: [.like: 2]
        )
        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: SampleProfileID.maya,
            activeBoardWeek: activeWeek
        )

        store.applyRemoteReactionChange(
            ReactionRealtimeChange(
                postID: post.id,
                userID: SampleProfileID.leo,
                previousType: nil,
                newType: .hug
            )
        )
        #expect(store.post(with: post.id)?.reactionCounts[.hug] == 1)
        #expect(store.post(with: post.id)?.reactionCounts[.like] == 2)

        store.applyRemoteReactionChange(
            ReactionRealtimeChange(
                postID: post.id,
                userID: SampleProfileID.leo,
                previousType: .hug,
                newType: .laugh
            )
        )
        #expect(store.post(with: post.id)?.reactionCounts[.hug] == nil)
        #expect(store.post(with: post.id)?.reactionCounts[.laugh] == 1)
    }

    @Test @MainActor func remoteReactionChangeIgnoresCurrentUser() {
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

        store.applyRemoteReactionChange(
            ReactionRealtimeChange(
                postID: post.id,
                userID: SampleProfileID.maya,
                previousType: nil,
                newType: .like
            )
        )
        #expect(store.post(with: post.id)?.reactionCounts[.like] == nil)
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
}

struct ProfileIndexTests {
    @Test func looksUpByHandleCaseInsensitively() {
        let index = ProfileIndex(profiles: Profile.samples)
        #expect(index.profile(handle: "MAYA.C")?.id == SampleProfileID.maya)
        #expect(index.profile(id: SampleProfileID.leo)?.handle == "leokp")
    }
}

struct CommentTreeBuilderTests {
    @Test func buildsNestedReplies() {
        let rootID = UUID()
        let replyID = UUID()
        let flat: [CommentTreeBuilder.FlatComment] = [
            .init(
                id: rootID,
                authorId: SampleProfileID.maya,
                author: "maya.c",
                body: "root",
                parentCommentId: nil,
                likeCount: 2,
                dislikeCount: 0,
                createdAt: .now
            ),
            .init(
                id: replyID,
                authorId: SampleProfileID.leo,
                author: "leokp",
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

struct MockOnboardingServiceTests {
    @Test func phoneUserStartsAtUsername() async throws {
        let defaults = UserDefaults(suiteName: "MockOnboardingPhone")!
        defaults.removePersistentDomain(forName: "MockOnboardingPhone")

        let auth = MockAuthService(defaults: defaults)
        _ = try await auth.verifyPhoneOTP(phone: "+15555550100", token: "123456")

        let onboarding = MockOnboardingService(defaults: defaults)
        let status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .username)
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

        _ = try await onboarding.completeProfile(displayName: "New Tester", bio: "Hello", avatarEmoji: "✨")
        status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .schoolVerify)

        _ = try await onboarding.beginSchoolEmailVerification("student@example.edu")
        _ = try await onboarding.completeSchoolEmailVerification("student@example.edu")
        status = try await onboarding.fetchStatus()
        #expect(status.onboardingStep == .waitlist)

        _ = try await onboarding.joinWaitlist()
        status = try await onboarding.fetchStatus()
        #expect(status.isComplete)
    }
}

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
}
