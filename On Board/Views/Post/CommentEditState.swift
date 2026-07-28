//
//  CommentEditState.swift
//  On Board
//
//  PostDetailView's "editing an existing comment in place" state, pulled out
//  alongside CommentComposerState (composing a new one) so the view's own
//  @State surface only has to track what's uniquely its own.
//

import Foundation
import Observation

@Observable
@MainActor
final class CommentEditState {
    var editingCommentID: UUID?
    var draftCommentBody = ""

    var isEditing: Bool { editingCommentID != nil }

    func begin(commentID: UUID, body: String) {
        editingCommentID = commentID
        draftCommentBody = body
    }

    func clear() {
        editingCommentID = nil
        draftCommentBody = ""
    }
}
