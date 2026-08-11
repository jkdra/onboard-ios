//
//  CommentTreeBuilderTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

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
