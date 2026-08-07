//
//  Post+Samples.swift
//  On Board
//
//  Sample posts double as the rich-text test sheet: the mix deliberately
//  covers every markup feature (headings, subtitles, bullets, bold, italic,
//  underline, strikethrough, stacked ***bold-italic***) AND the syntax's
//  guard rails (a literal #hashtag, mid-line #, asterisk arithmetic — none of
//  which may format). Several posts are heading-less one-liners on purpose:
//  that's the new normal, not a degenerate case.
//

import Foundation

extension Post {
    static let samples: [Post] = [
        sample(
            author: "maya.c",
            tone: .green,
            content: "**brat** by charli xcx is literally album of the year. i cant stop listening. it's been on repeat for *4 days straight* and my roommate is begging me to stop playing 360 but i refuse\n\n#music #charlixcx",
            reactionCounts: [.like: 89, .laugh: 12],
            comments: Comment.cs241MidtermComments // Reusing comments for simplicity
        ),
        sample(
            author: "maya.c",
            tone: .orange,
            content: """
            # anyone else fail the cs241 midterm
            felt like none of that was even in the lectures. avg was 47 according to my TA so ~~we're cooked~~ maybe the curve carries us. tell me im not alone in this
            
            #cs241 #midterms #venting
            """,
            reactionCounts: [.like: 40, .hug: 21, .laugh: 4],
            comments: Comment.cs241MidtermComments
        ),
        sample(
            author: "leokp",
            tone: .blue,
            content: """
            # selling math239 textbook $40 obo
            barely used. condition report:
            * two pages of highlighter
            * one (1) coffee ring
            * spine __never cracked__
            dm me, can meet outside dc library
            
            #forsale #math239
            """,
            reactionCounts: [.like: 15],
            comments: Comment.textbookComments
        ),
        sample(
            author: "laylah",
            tone: .pink,
            content: """
            # lost: black hydroflask, dc basement
            covered in stickers, one says 'do not crash'. left it on a table monday around 2am while i was crying over assembly. pls help i need water to live
            
            #lost-and-found
            """,
            reactionCounts: [.like: 9, .hug: 19],
            comments: Comment.hydroflaskComments,
            imageUrl: "https://loremflickr.com/900/600/hydroflask?lock=7",
            imageAspectRatio: 1.5
        ),
        sample(
            author: "danielr",
            tone: .red,
            // Deliberately heading-less + a mid-line capital rant: the card's
            // anchor is just the post itself.
            content: "ive been standing in the tims line for 18 minutes for an iced cap. they are **STAFFED**. multiple humans behind the counter. *nothing is happening*. send help\n\n#venting #coffee",
            reactionCounts: [.laugh: 47, .like: 22, .hug: 6],
            comments: Comment.timsLineComments,
            imageUrl: "https://loremflickr.com/800/600/coffee,shop?lock=3",
            imageAspectRatio: 1.333
        ),
        sample(
            author: "priyas",
            tone: .purple,
            content: """
            # econ 201 study group?
            midterm is in **11 days** and i havent opened the textbook once. looking for ppl who actually want to grind. ill bring munchies
            
            #econ201 #study-group
            """,
            reactionCounts: [.like: 21, .hug: 3],
            comments: Comment.econStudyComments
        ),
        sample(
            author: "marcus.l",
            tone: .yellow,
            // Syntax guard-rail showcase: "$7 * 4 * 12" must stay arithmetic.
            // "#not-sponsored" is now a real inline tag — but it's this post's
            // 4th, so it renders highlighted while the silent cap keeps it out
            // of the tags index. "#1"-style number-only tokens stay literal.
            content: "if my roommate drinks my oat milk ***one more time*** im labelling it with chemistry hazard symbols. it costs SEVEN dollars. thats $7 * 4 * 12 a year of theft. have mercy #not-sponsored\n\n#venting #roommates",
            reactionCounts: [.laugh: 33, .like: 14, .hug: 9, .dislike: 1],
            comments: Comment.oatMilkComments
        ),
        sample(
            author: "saraa",
            tone: .pink,
            content: """
            # FREE PIZZA mc 4022 rn
            software eng club meeting, like 4 untouched boxes. get over here before engsoc smells it and ransacks the place
            
            #free-food #promo
            """,
            reactionCounts: [.like: 59, .laugh: 6],
            comments: Comment.freePizzaComments,
            imageUrl: "https://loremflickr.com/800/500/pizzabox?lock=5",
            imageAspectRatio: 1.6
        ),
        sample(
            author: "jordank",
            tone: .indigo,
            content: "is anyones wifi being weird. eduroam is held together with two paperclips and a prayer. trying to submit my lab and im in *physical pain*\n\n#venting #wifi",
            reactionCounts: [.like: 19, .hug: 12, .laugh: 4],
            comments: Comment.wifiComments
        ),
        sample(
            author: "rileyc",
            tone: .mint,
            content: """
            # the squirrels are getting too brave
            one of them made __direct eye contact__ w me today while i was eating a granola bar. i felt threatened. should we be worried
            
            #campus-life #funny
            """,
            reactionCounts: [.laugh: 52, .like: 17, .hug: 2],
            comments: Comment.squirrelComments,
            imageUrl: "https://loremflickr.com/1000/600/squirrel?lock=9",
            imageAspectRatio: 1.667
        ),
        sample(
            author: "quinnm",
            tone: .blue,
            content: """
            # to whoever took my umbrella
            it was the only one i had. i hope it inverts on you in the worst possible moment. also if you have a heart pls return it, second floor mc by the vending machines
            
            #lost-and-found #venting
            """,
            reactionCounts: [.like: 23, .laugh: 11, .dislike: 2, .hug: 5],
            comments: Comment.umbrellaComments
        ),
        sample(
            author: "noraf",
            tone: .indigo,
            content: "watched the gta6 trailer again for the 400th time. i can hear the music in my sleep. rockstar is ~~playing with our lives~~ building anticipation pushing it back again istg. someone talk me off the ledge\n\n#gta6 #gaming",
            reactionCounts: [.laugh: 61, .like: 38, .hug: 3],
            comments: Comment.gta6Comments
        ),
        sample(
            author: "benw",
            tone: .teal,
            content: "transferred in this semester, still figuring out where anything is. 3 weeks in and i just found out there's a whole second cafeteria. also does anyone know how the printing credits work bc i think ive already gone into printing debt\n\n#transfer #campus-life",
            reactionCounts: [.hug: 24, .like: 18, .laugh: 9],
            comments: Comment.transferComments
        ),
        sample(
            author: "kevinz",
            tone: .yellow,
            content: """
            # biz society mixer thursday
            ## free boba for the first 50
            networking event but we kept it chill, *no blazers required*. mc atrium 6pm. boba from the place on king st, **not the sus one**
            
            #promo #events
            """,
            reactionCounts: [.like: 44, .laugh: 5],
            comments: Comment.bizMixerComments
        ),
        sample(
            author: "tylerb",
            tone: .red,
            content: "my roommate does dishes exactly once a month. its always the day before his parents visit. otherwise the sink is a science experiment. i live with a man who treats a sponge like its cursed\n\n#venting #roommates",
            reactionCounts: [.laugh: 39, .like: 20, .dislike: 2],
            comments: Comment.dishesComments
        ),
        sample(
            author: "zainabr",
            tone: .purple,
            content: "does anyone else do their best thinking at 2am in the library. im not even studying anymore im just sitting here having a full emotional realization about my life choices. the library at 2am is a *whole different dimension*\n\n#self-expression #3am-thoughts",
            reactionCounts: [.like: 47, .hug: 22, .laugh: 6],
            comments: Comment.libraryThoughtsComments
        ),
        sample(
            author: "laylah",
            tone: .green,
            content: """
            # eng society hackathon signups close friday
            * 24 hrs
            * free food **the entire time**
            * prizes for top 3
            no experience needed we WILL pair you with people who know what theyre doing. sign up link in the group chat
            
            #promo #engineering #events
            """,
            reactionCounts: [.like: 31, .laugh: 2],
            comments: Comment.hackathonComments
        ),
        sample(
            author: "saraa",
            tone: .orange,
            content: "sat outside today between classes and just felt happy for no reason. college is stressful but also kind of *magic* sometimes. anyway thats my ted talk\n\n#self-expression",
            reactionCounts: [.like: 58, .hug: 14],
            comments: Comment.gratefulComments
        ),
        sample(
            author: "leokp",
            tone: .pink,
            content: """
            # to the girl reading camus in the tim hortons on monday
            you laughed at something on your phone and i have thought about it every day since. this is __deeply embarrassing__ to post but here we are. reply if this was you (it *probably* wasnt but let a guy dream)
            
            #missed-connections #self-expression
            """,
            reactionCounts: [.laugh: 72, .like: 41, .hug: 9],
            comments: Comment.missedConnectionComments
        ),
    ]

    private static func sample(
        author: String,
        tone: PostTone,
        content: String,
        reactionCounts: [Reaction: Int],
        comments: [Comment],
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil
    ) -> Post {
        Post(
            authorId: Profile.lookup(handle: author)?.id,
            content: content,
            author: author,
            tone: tone,
            reactionCounts: reactionCounts,
            comments: comments,
            imageUrl: imageUrl,
            imageAspectRatio: imageAspectRatio
        )
    }
}
