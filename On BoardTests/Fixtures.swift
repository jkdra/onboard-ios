//
//  Fixtures.swift
//  On BoardTests
//
//  Shared service stubs used across the unit-test suites.
//

import Foundation
import Testing
@testable import On_Board

final class MockBoardService: BoardService, @unchecked Sendable {
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
    func createPost(weekID: UUID, authorID: UUID, content: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post {
        Post(authorId: authorID, boardWeekId: weekID, content: content, author: "maya.c", tone: tone, imageUrl: imageUrl, imageAspectRatio: imageAspectRatio)
    }
    func updatePost(id: UUID, content: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { throw BoardServiceError.notConfigured }
    func deletePost(id: UUID) async throws {}
    func createComment(postID: UUID, authorID: UUID, authorHandle: String, body: String, parentCommentID: UUID?) async throws -> On_Board.Comment {
        On_Board.Comment(authorId: authorID, author: authorHandle, body: body)
    }
    func updateComment(id: UUID, body: String) async throws {}
    func deleteComment(id: UUID) async throws {}
    func setReaction(postID: UUID, userID: UUID, reaction: Reaction?) async throws {}
    func updateProfile(id: UUID, displayName: String, handle: String, bio: String?, avatarUrl: String?, birthday: String?, showBirthday: Bool?) async throws -> Profile { throw BoardServiceError.notConfigured }
    func checkHandleAvailable(_ handle: String) async throws -> Bool { true }
    var reportContentError: Error?
    func reportContent(targetType: ReportTargetType, targetID: UUID, reason: ReportReason, details: String?) async throws {
        if let reportContentError { throw reportContentError }
    }
    var blockUserError: Error?
    func blockUser(blockedID: UUID) async throws {
        if let blockUserError { throw blockUserError }
    }
    var unblockUserError: Error?
    func unblockUser(blockedID: UUID) async throws {
        if let unblockUserError { throw unblockUserError }
    }
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
}

/// AuthService stub whose restore/sign-out behavior is scripted per test.
/// Every other requirement is unreachable in these tests.
final class ScriptedAuthService: AuthService, @unchecked Sendable {
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
    func checkPhoneExists(phone: String) async throws -> Bool { fatalError("unused") }
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
