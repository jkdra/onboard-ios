//
//  CommentThreadCountTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct CommentThreadCountTests {
    @Test func leafCountsItself() {
        let leaf = Comment(author: "a", body: "leaf")
        #expect(leaf.threadCount == 1)
    }

    @Test func threadCountIncludesAllDescendants() {
        let grandchildA = Comment(author: "c", body: "gc-a")
        let grandchildB = Comment(author: "d", body: "gc-b")
        let childWithKids = Comment(author: "b", body: "child", replies: [grandchildA, grandchildB])
        let childLeaf = Comment(author: "e", body: "leaf child")
        let root = Comment(author: "a", body: "root", replies: [childWithKids, childLeaf])

        #expect(root.threadCount == 5)
        // The "Show N replies" pill shows descendants only:
        #expect(root.threadCount - 1 == 4)
    }
}
