//
//  CommentComposerState.swift
//  On Board
//
//  State machine for PostDetailView's bottom comment composer. Pure value
//  type so target/draft transitions are unit-testable without SwiftUI.
//

import Foundation

enum ComposerTarget: Equatable {
    case newComment
    case reply(parentID: UUID, handle: String)

    var isReply: Bool {
        if case .reply = self { return true }
        return false
    }

    var replyParentID: UUID? {
        if case .reply(let parentID, _) = self { return parentID }
        return nil
    }
}

struct CommentComposerState: Equatable {
    /// Shared with CommentView's edit-in-place draft, which composes a comment
    /// body the same way but doesn't route through this type.
    static let maxLength = 280

    private(set) var target: ComposerTarget?
    var draft: String = ""

    var isComposing: Bool { target != nil }

    mutating func beginNewComment() {
        target = .newComment
    }

    mutating func beginReply(parentID: UUID, handle: String) {
        target = .reply(parentID: parentID, handle: handle)
    }

    /// Reply chip ✕: keep composing, but as a top-level comment.
    mutating func clearReplyTarget() {
        if target?.isReply == true { target = .newComment }
    }

    /// Composer ✕ / keyboard dismiss: back to browse. A non-empty draft
    /// survives for the session so an accidental dismiss never loses writing.
    mutating func dismiss() {
        target = nil
        if draft.trimmed.isEmpty { draft = "" }
    }

    /// Successful post: back to browse with a clean slate.
    mutating func finishPosting() {
        target = nil
        draft = ""
    }
}
