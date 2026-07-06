//
//  BoardStore+Lookups.swift
//  On Board
//
//  Current-user/ownership lookups and interaction-gating checks. None of
//  these touch BoardStore's private caching dicts directly — they only read
//  already-internal properties (currentUserID, boardWeeks, activeBoardWeek)
//  or call other BoardStore methods — so nothing here needed any access
//  widening to move out of BoardStore.swift.
//

import Foundation

extension BoardStore {
    func comments(for postID: UUID) -> [Comment] {
        commentsByPostID[postID] ?? []
    }

    var currentBoardWeeks: [BoardWeek] {
        guard let boardID = currentBoardId else { return boardWeeks }
        return boardWeeks.filter { $0.boardId == boardID }
    }

    var clearingBannerText: String? {
        BoardSchedule.finalHourBannerText(weekEnd: activeBoardWeek?.endsAt)
    }

    var canInteractWithBoard: Bool {
        guard let activeBoardWeek else { return false }
        return canInteract(with: activeBoardWeek)
    }

    func canInteract(with week: BoardWeek) -> Bool {
        week.status == .active
            && week.id == activeBoardWeek?.id
            && week.boardId == currentBoardId
    }

    func canInteract(with post: Post) -> Bool {
        canInteractWithBoard && !post.isReadOnly
    }

    var currentUser: Profile? {
        guard let currentUserID else { return nil }
        return profile(id: currentUserID)
    }

    func setCurrentUser(id: UUID) {
        currentUserID = id
    }

    func clearCurrentUser() {
        currentUserID = nil
    }

    func post(with id: UUID) -> Post? {
        guard var post = feedPost(id: id) else { return nil }
        post.comments = comments(for: id)
        return post
    }

    func canEdit(post: Post) -> Bool {
        isOwned(by: post.authorId, authorHandle: post.author)
    }

    func canEdit(comment: Comment) -> Bool {
        isOwned(by: comment.authorId, authorHandle: comment.author)
    }

    func canEdit(profile: Profile) -> Bool {
        guard let currentUserID else { return false }
        return profile.id == currentUserID
    }

    func isOwned(by authorId: UUID?, authorHandle: String) -> Bool {
        guard let currentUserID else { return false }
        if let authorId { return authorId == currentUserID }
        return currentUser?.handle.compare(authorHandle, options: .caseInsensitive) == .orderedSame
    }

    @discardableResult
    func mutateComments(for postID: UUID, _ transform: (inout [Comment]) -> Bool) -> Bool {
        guard var thread = commentsByPostID[postID] else { return false }
        let changed = transform(&thread)
        if changed {
            commentsByPostID[postID] = thread
        }
        return changed
    }
}
