//
//  Post+Samples.swift
//  On Board
//

import Foundation

extension Post {
    static let samples: [Post] = [
        sample(
            author: "maya.c",
            tone: .green,
            title: "brat by charli xcx is literally album of the year",
            description: "i cant stop listening. it's been on repeat for 4 days straight and my roommate is begging me to stop playing 360 but i refuse",
            reactionCounts: [.like: 89, .laugh: 12],
            comments: Comment.cs241MidtermComments, // Reusing comments for simplicity
            tags: ["music", "charlixcx"]
        ),
        sample(
            author: "maya.c",
            tone: .orange,
            title: "anyone else fail the cs241 midterm",
            description: "felt like none of that was even in the lectures. avg was 47 according to my TA so maybe the curve carries us. tell me im not alone in this",
            reactionCounts: [.like: 40, .hug: 21, .laugh: 4],
            comments: Comment.cs241MidtermComments,
            tags: ["cs241", "midterms", "venting"]
        ),
        sample(
            author: "leokp",
            tone: .blue,
            title: "selling math239 textbook $40 obo",
            description: "barely used. two pages of highlighter and one (1) coffee ring. dm me, can meet outside dc library",
            reactionCounts: [.like: 15],
            comments: Comment.textbookComments,
            tags: ["forsale", "math239"]
        ),
        sample(
            author: "laylah",
            tone: .pink,
            title: "lost: black hydroflask, dc basement",
            description: "covered in stickers, one says 'do not crash'. left it on a table monday around 2am while i was crying over assembly. pls help i need water to live",
            reactionCounts: [.like: 9, .hug: 19],
            comments: Comment.hydroflaskComments,
            imageUrl: "https://loremflickr.com/900/600/hydroflask?lock=7",
            imageAspectRatio: 1.5,
            tags: ["lost-and-found"]
        ),
        sample(
            author: "danielr",
            tone: .red,
            title: "why is the tims line like this",
            description: "ive been standing here for 18 minutes for an iced cap. they are STAFFED. multiple humans behind the counter. nothing is happening. send help",
            reactionCounts: [.laugh: 47, .like: 22, .hug: 6],
            comments: Comment.timsLineComments,
            imageUrl: "https://loremflickr.com/800/600/coffee,shop?lock=3",
            imageAspectRatio: 1.333,
            tags: ["venting", "coffee"]
        ),
        sample(
            author: "priyas",
            tone: .purple,
            title: "econ 201 study group?",
            description: "midterm is in 11 days and i havent opened the textbook once. looking for ppl who actually want to grind. ill bring munchies",
            reactionCounts: [.like: 21, .hug: 3],
            comments: Comment.econStudyComments,
            tags: ["econ201", "study-group"]
        ),
        sample(
            author: "marcus.l",
            tone: .yellow,
            title: "the oat milk situation",
            description: "if my roommate drinks my oat milk one more time im genuinely going to start labelling it with chemistry hazard symbols. it costs SEVEN dollars. have mercy",
            reactionCounts: [.laugh: 33, .like: 14, .hug: 9, .dislike: 1],
            comments: Comment.oatMilkComments,
            tags: ["venting", "roommates"]
        ),
        sample(
            author: "saraa",
            tone: .pink,
            title: "FREE PIZZA mc 4022 rn",
            description: "software eng club meeting, like 4 untouched boxes. get over here before engsoc smells it and ransacks the place",
            reactionCounts: [.like: 59, .laugh: 6],
            comments: Comment.freePizzaComments,
            imageUrl: "https://loremflickr.com/800/500/pizzabox?lock=5",
            imageAspectRatio: 1.6,
            tags: ["free-food", "promo"]
        ),
        sample(
            author: "jordank",
            tone: .indigo,
            title: "is anyones wifi being weird",
            description: "eduroam is held together with two paperclips and a prayer. trying to submit my lab and im in physical pain",
            reactionCounts: [.like: 19, .hug: 12, .laugh: 4],
            comments: Comment.wifiComments,
            tags: ["venting", "wifi"]
        ),
        sample(
            author: "rileyc",
            tone: .mint,
            title: "the squirrels are getting too brave",
            description: "one of them made direct eye contact w me today while i was eating a granola bar. i felt threatened. should we be worried",
            reactionCounts: [.laugh: 52, .like: 17, .hug: 2],
            comments: Comment.squirrelComments,
            imageUrl: "https://loremflickr.com/1000/600/squirrel?lock=9",
            imageAspectRatio: 1.667,
            tags: ["campus-life", "funny"]
        ),
        sample(
            author: "quinnm",
            tone: .blue,
            title: "to whoever took my umbrella",
            description: "it was the only one i had. i hope it inverts on you in the worst possible moment. also if you have a heart pls return it, second floor mc by the vending machines",
            reactionCounts: [.like: 23, .laugh: 11, .dislike: 2, .hug: 5],
            comments: Comment.umbrellaComments,
            tags: ["lost-and-found", "venting"]
        ),
        sample(
            author: "noraf",
            tone: .indigo,
            title: "the gta6 trailer again for the 400th time",
            description: "i have watched it so many times i can hear the music in my sleep. rockstar is playing with our lives pushing it back again istg. someone talk me off the ledge",
            reactionCounts: [.laugh: 61, .like: 38, .hug: 3],
            comments: Comment.gta6Comments,
            tags: ["gta6", "gaming"]
        ),
        sample(
            author: "benw",
            tone: .teal,
            title: "transferred in this semester, still figuring out where anything is",
            description: "3 weeks in and i just found out there's a whole second cafeteria. also does anyone know how the printing credits work bc i think ive already gone into printing debt",
            reactionCounts: [.hug: 24, .like: 18, .laugh: 9],
            comments: Comment.transferComments,
            tags: ["transfer", "campus-life"]
        ),
        sample(
            author: "kevinz",
            tone: .yellow,
            title: "biz society mixer thursday, free boba for the first 50",
            description: "networking event but we kept it chill, no blazers required. mc atrium 6pm. boba from the place on king st, not the sus one",
            reactionCounts: [.like: 44, .laugh: 5],
            comments: Comment.bizMixerComments,
            tags: ["promo", "events"]
        ),
        sample(
            author: "tylerb",
            tone: .red,
            title: "my roommate does dishes exactly once a month",
            description: "its always the day before his parents visit. otherwise the sink is a science experiment. i live with a man who treats a sponge like its cursed",
            reactionCounts: [.laugh: 39, .like: 20, .dislike: 2],
            comments: Comment.dishesComments,
            tags: ["venting", "roommates"]
        ),
        sample(
            author: "zainabr",
            tone: .purple,
            title: "does anyone else do their best thinking at 2am in the library",
            description: "im not even studying anymore im just sitting here having a full emotional realization about my life choices. the library at 2am is a whole different dimension",
            reactionCounts: [.like: 47, .hug: 22, .laugh: 6],
            comments: Comment.libraryThoughtsComments,
            tags: ["self-expression", "3am-thoughts"]
        ),
        sample(
            author: "laylah",
            tone: .green,
            title: "eng society hackathon signups close friday",
            description: "24 hrs, free food the entire time, prizes for top 3. no experience needed we WILL pair you with people who know what theyre doing. sign up link in the group chat",
            reactionCounts: [.like: 31, .laugh: 2],
            comments: Comment.hackathonComments,
            tags: ["promo", "engineering", "events"]
        ),
        sample(
            author: "saraa",
            tone: .orange,
            title: "grateful for this weird little chapter of life",
            description: "sat outside today between classes and just felt happy for no reason. college is stressful but also kind of magic sometimes. anyway thats my ted talk",
            reactionCounts: [.like: 58, .hug: 14],
            comments: Comment.gratefulComments,
            tags: ["self-expression"]
        ),
        sample(
            author: "leokp",
            tone: .pink,
            title: "to the girl reading camus in the tim hortons on monday",
            description: "you laughed at something on your phone and i have thought about it every day since. this is deeply embarrassing to post but here we are. reply if this was you (it probably wasnt but let a guy dream)",
            reactionCounts: [.laugh: 72, .like: 41, .hug: 9],
            comments: Comment.missedConnectionComments,
            tags: ["missed-connections", "self-expression"]
        ),
    ]

    private static func sample(
        author: String,
        tone: PostTone,
        title: String,
        description: String,
        reactionCounts: [Reaction: Int],
        comments: [Comment],
        imageUrl: String? = nil,
        imageAspectRatio: Double? = nil,
        tags: [String] = []
    ) -> Post {
        Post(
            authorId: Profile.lookup(handle: author)?.id,
            title: title,
            description: description,
            author: author,
            tone: tone,
            reactionCounts: reactionCounts,
            comments: comments,
            imageUrl: imageUrl,
            imageAspectRatio: imageAspectRatio,
            tags: tags
        )
    }
}
