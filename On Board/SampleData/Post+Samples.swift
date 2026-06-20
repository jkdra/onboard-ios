//
//  Post+Samples.swift
//  On Board
//

import Foundation

extension Post {
    static let samples: [Post] = [
        sample(
            author: "maya.c",
            title: "anyone else fail the cs241 midterm",
            description: "felt like none of that was even in the lectures. avg was 47 according to my TA so maybe the curve carries us. tell me im not alone in this",
            reactionCounts: [.like: 40, .hug: 21, .laugh: 4],
            comments: Comment.cs241MidtermComments
        ),
        sample(
            author: "leokp",
            title: "selling math239 textbook $40 obo",
            description: "barely used. two pages of highlighter and one (1) coffee ring. dm me, can meet outside dc library",
            reactionCounts: [.like: 15],
            comments: Comment.textbookComments
        ),
        sample(
            author: "aishap",
            title: "lost: black hydroflask, dc basement",
            description: "covered in stickers, one says 'do not crash'. left it on a table monday around 2am while i was crying over assembly. pls help i need water to live",
            reactionCounts: [.like: 9, .hug: 19],
            comments: Comment.hydroflaskComments
        ),
        sample(
            author: "danielr",
            title: "why is the tims line like this",
            description: "ive been standing here for 18 minutes for an iced cap. they are STAFFED. multiple humans behind the counter. nothing is happening. send help",
            reactionCounts: [.laugh: 47, .like: 22, .hug: 6],
            comments: Comment.timsLineComments
        ),
        sample(
            author: "priyas",
            title: "econ 201 study group?",
            description: "midterm is in 11 days and i havent opened the textbook once. looking for ppl who actually want to grind. ill bring munchies",
            reactionCounts: [.like: 21, .hug: 3],
            comments: Comment.econStudyComments
        ),
        sample(
            author: "marcus.l",
            title: "the oat milk situation",
            description: "if my roommate drinks my oat milk one more time im genuinely going to start labelling it with chemistry hazard symbols. it costs SEVEN dollars. have mercy",
            reactionCounts: [.laugh: 33, .like: 14, .hug: 9, .dislike: 1],
            comments: Comment.oatMilkComments
        ),
        sample(
            author: "saraa",
            title: "FREE PIZZA mc 4022 rn",
            description: "software eng club meeting, like 4 untouched boxes. get over here before engsoc smells it and ransacks the place",
            reactionCounts: [.like: 59, .laugh: 6],
            comments: Comment.freePizzaComments
        ),
        sample(
            author: "jordank",
            title: "is anyones wifi being weird",
            description: "eduroam is held together with two paperclips and a prayer. trying to submit my lab and im in physical pain",
            reactionCounts: [.like: 19, .hug: 12, .laugh: 4],
            comments: Comment.wifiComments
        ),
        sample(
            author: "rileyc",
            title: "the squirrels are getting too brave",
            description: "one of them made direct eye contact w me today while i was eating a granola bar. i felt threatened. should we be worried",
            reactionCounts: [.laugh: 52, .like: 17, .hug: 2],
            comments: Comment.squirrelComments
        ),
        sample(
            author: "quinnm",
            title: "to whoever took my umbrella",
            description: "it was the only one i had. i hope it inverts on you in the worst possible moment. also if you have a heart pls return it, second floor mc by the vending machines",
            reactionCounts: [.like: 23, .laugh: 11, .dislike: 2, .hug: 5],
            comments: Comment.umbrellaComments
        )
    ]

    private static func sample(
        author: String,
        title: String,
        description: String,
        reactionCounts: [Reaction: Int],
        comments: [Comment]
    ) -> Post {
        Post(
            authorId: Profile.lookup(handle: author)?.id,
            title: title,
            description: description,
            author: author,
            reactionCounts: reactionCounts,
            comments: comments
        )
    }
}
