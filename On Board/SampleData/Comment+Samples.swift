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
            .authored(by: "zainabr", body: "lmao no its black. solidarity tho")
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
        .authored(by: "laylah", body: "its not just you, the whole north campus is down rn"),
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

    static let gta6Comments: [Comment] = [
        .authored(by: "kevinz", body: "bro its literally still 2 years away and i am already emotionally invested"),
        .authored(by: "benw", body: "the fact it costs more than my tuition per credit and im still buying it", replies: [
            .authored(by: "noraf", body: "we are not the same but also yes i will be there day one")
        ]),
        Comment(author: "anon", body: "rockstar could delay it to 2030 and people would still preorder")
    ]

    static let transferComments: [Comment] = [
        .authored(by: "maya.c", body: "welcome!! the second cafeteria in slc is actually the good one dont sleep on it"),
        .authored(by: "zainabr", body: "printing credits reset every term, go to the it help desk they can top you up"),
        Comment(author: "anon", body: "ngl took me a full semester to find the quiet floor in the library too, ur ahead of schedule")
    ]

    static let bizMixerComments: [Comment] = [
        .authored(by: "leokp", body: "the boba alone is worth the small talk"),
        .authored(by: "priyas", body: "is this the one with the raffle for airpods or am i thinking of a different one", replies: [
            .authored(by: "kevinz", body: "different event but also yes there will be a raffle")
        ]),
        Comment(author: "sam.t", body: "do i need to bring a resume or is this chill")
    ]

    static let dishesComments: [Comment] = [
        .authored(by: "marcus.l", body: "the oat milk incident has entered the chat, we should start a support group"),
        .authored(by: "benw", body: "put a sticky note on it that says 'day 47'. shame is a powerful motivator", replies: [
            .authored(by: "tylerb", body: "i am absolutely doing this tonight")
        ]),
        Comment(author: "anon", body: "this is why i live alone and talk to no one")
    ]

    static let libraryThoughtsComments: [Comment] = [
        .authored(by: "saraa", body: "the 2am library energy is unmatched, its like a different planet"),
        .authored(by: "danielr", body: "i had a full life realization at the dc printers once, we've all been there", replies: [
            .authored(by: "zainabr", body: "the printers really do double as a confessional")
        ]),
        Comment(author: "anon", body: "sending love, also maybe go to sleep")
    ]

    static let hackathonComments: [Comment] = [
        .authored(by: "kevinz", body: "signed up with zero coding experience last year and somehow we placed top 3, do it"),
        .authored(by: "jordank", body: "is the food actually good or is it just pizza the whole 24 hours", replies: [
            .authored(by: "laylah", body: "we upgraded the food this year i promise, theres a taco truck at hour 12")
        ]),
        Comment(author: "anon", body: "signing up purely for the taco truck ngl")
    ]

    static let gratefulComments: [Comment] = [
        .authored(by: "priyas", body: "this is such a nice post, needed this today"),
        .authored(by: "rileyc", body: "the little moments really do carry the whole semester"),
        Comment(author: "anon", body: "ok this made my day a little better thank u")
    ]

    static let missedConnectionComments: [Comment] = [
        .authored(by: "maya.c", body: "this is either the most romantic or most unhinged post ive seen on here and i respect it"),
        .authored(by: "noraf", body: "camus in a tim hortons is such specific main character energy", replies: [
            .authored(by: "leokp", body: "i thought so too in the moment, still thinking about it now")
        ]),
        Comment(author: "anon", body: "if this is about who i think it is, she comes in every monday at 2, good luck man")
    ]
}
