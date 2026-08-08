//
//  BoardSwitchRaceTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct BoardSwitchRaceTests {
    /// BoardService stub whose loadActiveBoard for a chosen board suspends until released.
    final class SlowBoardService: BoardService, @unchecked Sendable {
        var slowBoardID: UUID?
        private var continuation: CheckedContinuation<Void, Never>?

        // Separate slow-path for fetchComments, keyed by post rather than
        // board, so a comments-load race can be simulated independently of
        // the board-load race above.
        var slowCommentsPostID: UUID?
        var commentsToReturn = CommentThread(comments: [], userVotes: [:])
        private var commentsContinuation: CheckedContinuation<Void, Never>?

        func releaseSlowLoad() {
            continuation?.resume()
            continuation = nil
        }

        func releaseSlowComments() {
            commentsContinuation?.resume()
            commentsContinuation = nil
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
        func fetchComments(for postID: UUID) async throws -> CommentThread {
            if postID == slowCommentsPostID {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { self.commentsContinuation = $0 }
                } onCancel: {
                    Task { @MainActor in self.releaseSlowComments() }
                }
            }
            return commentsToReturn
        }
        func setCommentVote(commentID: UUID, postID: UUID, userID: UUID, vote: CommentVote?) async throws { fatalError("unused") }
        func createPost(weekID: UUID, authorID: UUID, content: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { fatalError("unused") }
        func updatePost(id: UUID, content: String, tone: PostTone, imageUrl: String?, imageAspectRatio: Double?, tags: [String]) async throws -> Post { fatalError("unused") }
        func deletePost(id: UUID) async throws { fatalError("unused") }
        func createComment(postID: UUID, authorID: UUID, authorHandle: String, body: String, parentCommentID: UUID?) async throws -> On_Board.Comment { fatalError("unused") }
        func updateComment(id: UUID, body: String) async throws { }
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

    // Regression test for the loadComments/local-mutation race: a background
    // revalidation's fetch can still be in flight when the user edits a
    // comment; the stale response landing afterward must not clobber the edit.
    @Test func loadCommentsDoesNotClobberAConcurrentLocalEdit() async {
        let boardID = UUID(), authorID = UUID(), commentID = UUID()
        let week = BoardWeek(
            boardId: boardID,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(604_800),
            status: .active
        )
        let originalComment = Comment(id: commentID, authorId: authorID, author: "maya", body: "original")
        let post = Post(
            authorId: authorID,
            boardWeekId: week.id,
            content: "t d",
            author: "maya",
            comments: [originalComment]
        )

        let service = SlowBoardService()
        service.slowCommentsPostID = post.id
        // The stale server snapshot the fetch will (eventually) return —
        // reflects the comment's body from before the local edit below.
        service.commentsToReturn = CommentThread(comments: [originalComment], userVotes: [:])

        let store = BoardStore(
            posts: [post],
            profiles: [],
            currentUserID: authorID,
            activeBoardWeek: week,
            boardWeeks: [week],
            currentBoard: Board(id: boardID, name: "Test"),
            boardService: service
        )

        let loadTask = Task { await store.loadComments(for: post.id) }
        await Task.yield()  // let the slow fetch start and suspend

        await store.updateComment(postID: post.id, commentID: commentID, body: "edited")
        #expect(store.comments(for: post.id).comment(with: commentID)?.body == "edited")

        service.releaseSlowComments()
        await loadTask.value

        // The stale fetch resolving afterward must not have reverted the edit.
        #expect(store.comments(for: post.id).comment(with: commentID)?.body == "edited")
    }
}
