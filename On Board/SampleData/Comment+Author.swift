//
//  Comment+Author.swift
//  On Board
//
//  Helpers for resolving comment authorship against the profile registry.
//

import Foundation

extension Comment {
    static func authored(
        by handle: String,
        body: String,
        replies: [Comment] = []
    ) -> Comment {
        Comment(
            authorId: Profile.lookup(handle: handle)?.id,
            author: handle,
            body: body,
            replies: replies
        )
    }
}
