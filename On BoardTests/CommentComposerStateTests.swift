//
//  CommentComposerStateTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct CommentComposerStateTests {
    private let parentID = UUID()

    @Test func startsInBrowseState() {
        let state = CommentComposerState()
        #expect(!state.isComposing)
        #expect(state.target == nil)
    }

    @Test func switchingTargetKeepsDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "half-written thought"
        state.beginReply(parentID: parentID, handle: "sarah")
        #expect(state.draft == "half-written thought")
        #expect(state.target == .reply(parentID: parentID, handle: "sarah"))
    }

    @Test func clearReplyTargetFallsBackToNewComment() {
        var state = CommentComposerState()
        state.beginReply(parentID: parentID, handle: "sarah")
        state.clearReplyTarget()
        #expect(state.target == .newComment)
        #expect(state.isComposing)
    }

    @Test func clearReplyTargetWhileBrowsingStaysBrowsing() {
        var state = CommentComposerState()
        state.clearReplyTarget()
        #expect(state.target == nil)
    }

    @Test func dismissRetainsNonEmptyDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "keep me"
        state.dismiss()
        #expect(!state.isComposing)
        #expect(state.draft == "keep me")
    }

    @Test func dismissClearsWhitespaceOnlyDraft() {
        var state = CommentComposerState()
        state.beginNewComment()
        state.draft = "   \n"
        state.dismiss()
        #expect(state.draft.isEmpty)
    }

    @Test func finishPostingClearsEverything() {
        var state = CommentComposerState()
        state.beginReply(parentID: parentID, handle: "sarah")
        state.draft = "posted!"
        state.finishPosting()
        #expect(state.target == nil)
        #expect(state.draft.isEmpty)
    }

    @Test func replyParentIDExtractsOnlyFromReplies() {
        var state = CommentComposerState()
        state.beginNewComment()
        #expect(state.target?.replyParentID == nil)
        state.beginReply(parentID: parentID, handle: "sarah")
        #expect(state.target?.replyParentID == parentID)
    }
}
