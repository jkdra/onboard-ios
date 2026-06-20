//
//  Comment+Samples.swift
//  On Board
//

import Foundation

extension Comment {
    static let cs241MidtermComments: [Comment] = [
        .authored(by: "leokp", body: "the dynamic programming q was illegal i swear", replies: [
            .authored(by: "maya.c", body: "second one or third one bc both were evil"),
            .authored(by: "leokp", body: "yes")
        ]),
        Comment(author: "anon", body: "yall need to start going to office hours fr"),
        .authored(by: "saraa", body: "average was actually 51 i checked learn. still cooked")
    ]

    static let textbookComments: [Comment] = [
        .authored(by: "priyas", body: "still available?", replies: [
            .authored(by: "leokp", body: "yep dm me")
        ]),
        Comment(author: "kev", body: "would u take 30")
    ]

    static let hydroflaskComments: [Comment] = [
        .authored(by: "danielr", body: "check lost and found at turnkey, they had like 6 last week"),
        .authored(by: "saraa", body: "if its blue with a sticker that says 'i miss my mom' that's mine sorry", replies: [
            .authored(by: "aishap", body: "lmao no its black. solidarity tho")
        ]),
        Comment(author: "ej", body: "rip bro hope u find it")
    ]

    static let timsLineComments: [Comment] = [
        .authored(by: "jordank", body: "this is canadas true national crisis"),
        .authored(by: "marcus.l", body: "skip it, the one in MC is empty rn", replies: [
            .authored(by: "danielr", body: "you're a hero")
        ]),
        Comment(author: "anon", body: "the iced caps just hit different when youve been waiting 20 min for them")
    ]

    static let econStudyComments: [Comment] = [
        .authored(by: "rileyc", body: "down. dc 1568 friday at 7?", replies: [
            .authored(by: "priyas", body: "ill be there w timbits")
        ]),
        .authored(by: "quinnm", body: "+1"),
        Comment(author: "ben.k", body: "is this open or like a closed thing", replies: [
            .authored(by: "priyas", body: "open come thru")
        ])
    ]

    static let oatMilkComments: [Comment] = [
        Comment(author: "anon", body: "switch to soy. nobody steals soy"),
        .authored(by: "maya.c", body: "put it in a hot sauce bottle. problem solved", replies: [
            .authored(by: "marcus.l", body: "you may have just changed my life")
        ]),
        Comment(author: "ej", body: "this is why i lock my mini fridge")
    ]

    static let freePizzaComments: [Comment] = [
        .authored(by: "leokp", body: "on my way"),
        .authored(by: "danielr", body: "is it still there", replies: [
            .authored(by: "saraa", body: "half a box of hawaiian left. you've been warned")
        ]),
        .authored(by: "rileyc", body: "got here too late. devastating")
    ]

    static let wifiComments: [Comment] = [
        .authored(by: "aishap", body: "its not just you, the whole north campus is down rn"),
        Comment(author: "ella", body: "ive been trying to ssh into student.cs for an hour. send help", replies: [
            .authored(by: "jordank", body: "we are all suffering together")
        ])
    ]

    static let squirrelComments: [Comment] = [
        .authored(by: "priyas", body: "the one near needles hall stole my entire sandwich last week. theyre organized"),
        .authored(by: "marcus.l", body: "theyre building something. mark my words", replies: [
            .authored(by: "rileyc", body: "the squirrel uprising is upon us")
        ]),
        Comment(author: "anon", body: "i for one welcome our new tree-dwelling overlords")
    ]

    static let umbrellaComments: [Comment] = [
        .authored(by: "saraa", body: "this is the most waterloo thing ive ever read"),
        .authored(by: "leokp", body: "i found one by the vending machines last week. blue, broken handle. yours?", replies: [
            .authored(by: "quinnm", body: "mine was black but ill take it at this point")
        ])
    ]
}
