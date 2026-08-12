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
//  They're also the App Store screenshots, so two content rules hold:
//
//  1. NOTHING NAMES A CAMPUS. No building codes, no local chains, no
//     campus-specific course numbers or society acronyms. Every location is
//     a thing every campus has ("the library", "the student union"), and
//     course codes are the generic kind ("stats 200"). One screenshot with
//     "DC basement" in it tells every reader which school this is, and
//     prices the app as that school's app.
//  2. IMAGES COME FROM ONE SAFE SOURCE. picsum.photos only, which serves
//     Unsplash photos: the Unsplash License grants commercial use with no
//     attribution. loremflickr (used here previously) serves Creative
//     Commons Flickr photos whose flavour varies PER IMAGE — several were
//     NonCommercial/NoDerivatives, which an App Store listing violates.
//     Pick a picsum id, LOOK at it, then write copy to match; never write
//     copy first and hunt for a photo (that's how a "free pizza" post
//     ended up illustrated with a cat statue). Avoid photos of
//     identifiable people — Unsplash's licence doesn't grant model
//     releases.
//  3. THE SPREAD IS THE PITCH. On Board is where campus social life lives,
//     so the mix reads as club mixers, club meetings, practical campus help,
//     and pure shitposting — in that proportion, not a wall of venting.
//
//  Feed/archive split (see BoardStore.previewBoard): the FIRST 8 are this
//  week's board and the LAST 10 are archived, so the count here must stay at
//  18 — anything in between is silently dropped from both.
//

import Foundation

extension Post {
    static let samples: [Post] = [

        // ─── This week's board (first 8) ────────────────────────────────

        // Clubs/events, and the fullest markup sample: heading, subtitle,
        // italic, bold.
        sample(
            author: "kevinz",
            tone: .yellow,
            content: """
            # design club mixer thursday
            ## free boba for the first 50
            networking night but we kept it chill, *no blazers required*. student union atrium, 6pm. **first-years especially welcome** — come alone, leave with a group chat

            #clubs #events
            """,
            reactionCounts: [.like: 44, .laugh: 5],
            comments: Comment.bizMixerComments
        ),
        // Short body-only post — exercises PostMarkup.bodyOnlyTier's
        // extraLarge rendering on the card and in detail. Also ANSWERS this
        // week's prompt: a board whose prompt has no replies under it reads
        // like a dead board, so a few posts always talk back to it.
        sample(
            author: "danielr",
            tone: .mint,
            content: "climbing club. went for the free intro session, now its my whole personality",
            reactionCounts: [.laugh: 31, .like: 12, .hug: 2],
            comments: []
        ),
        // Campus help: the "am i alone in this" post that makes a board feel
        // like a room full of people.
        sample(
            author: "maya.c",
            tone: .orange,
            content: """
            # anyone else fail the stats 200 midterm
            felt like none of that was in the lectures. average was a 47 so ~~we're cooked~~ maybe the curve saves us. tell me im not the only one

            #academics #midterms
            """,
            reactionCounts: [.like: 40, .hug: 21, .laugh: 4],
            comments: Comment.cs241MidtermComments
        ),
        // Marketplace + the bullet list, with an underline in the wild.
        sample(
            author: "leokp",
            tone: .blue,
            content: """
            # selling my stats textbook, $40 obo
            barely used. honest condition report:
            * two pages of highlighter
            * one (1) coffee ring
            * spine __never cracked__
            can meet outside the library any afternoon

            #for-sale #textbooks
            """,
            reactionCounts: [.like: 15],
            comments: Comment.textbookComments
        ),
        // Clubs again, from the other side: the free-food post that gets
        // people into a club room they'd never have walked into.
        sample(
            author: "saraa",
            tone: .pink,
            content: """
            # join the cooking club, im serious
            ## they always make *way* too much
            open to everyone, zero skills required. tonight they cooked for forty people and there are eleven of us. come eat

            #clubs #free-food
            """,
            reactionCounts: [.like: 59, .laugh: 6],
            comments: Comment.freePizzaComments,
            imageUrl: "https://picsum.photos/id/292/800/500",
            imageAspectRatio: 1.6
        ),
        // Shitposting, and a syntax guard-rail showcase: "$7 * 4 * 12" must
        // stay arithmetic, and "#not-sponsored" is a real inline tag but the
        // post's 4th — highlighted, yet silently kept out of the tag index.
        sample(
            author: "marcus.l",
            tone: .green,
            content: "if my roommate drinks my oat milk ***one more time*** im labelling it with chemistry hazard symbols. it costs SEVEN dollars. thats $7 * 4 * 12 a year of theft. have mercy #not-sponsored\n\n#venting #roommates",
            reactionCounts: [.laugh: 33, .like: 14, .hug: 9, .dislike: 1],
            comments: Comment.oatMilkComments
        ),
        // Practical help, with a photo.
        sample(
            author: "laylah",
            tone: .purple,
            content: """
            # lost: black water bottle, covered in stickers
            one of them says 'do not crash'. left it on a table monday around 2am while crying over a problem set. i need water to live

            #lost-and-found
            """,
            reactionCounts: [.like: 9, .hug: 19],
            comments: Comment.hydroflaskComments
        ),
        // Pure campus life — the post that has no purpose except being funny,
        // which is half of what a board is for.
        sample(
            author: "rileyc",
            tone: .teal,
            content: """
            # the squirrels are getting too brave
            one of them made __direct eye contact__ with me while i was eating a granola bar. i felt genuinely threatened. should we be worried

            #campus-life #funny
            """,
            reactionCounts: [.laugh: 52, .like: 17, .hug: 2],
            comments: Comment.squirrelComments
        ),

        // ─── Archived weeks (last 10) ───────────────────────────────────

        sample(
            author: "maya.c",
            tone: .green,
            content: "**brat** by charli xcx is literally album of the year. i cant stop listening. it's been on repeat for *4 days straight* and my roommate is begging me to stop playing 360 but i refuse\n\n#music #charlixcx",
            reactionCounts: [.like: 89, .laugh: 12],
            comments: Comment.cs241MidtermComments
        ),
        sample(
            author: "laylah",
            tone: .green,
            content: """
            # hackathon signups close friday
            * 24 hours
            * free food **the entire time**
            * prizes for the top 3
            no experience needed — we WILL pair you with people who know what theyre doing

            #clubs #events
            """,
            reactionCounts: [.like: 31, .laugh: 2],
            comments: Comment.hackathonComments
        ),
        sample(
            author: "priyas",
            tone: .purple,
            content: """
            # stats study group, anyone?
            midterm is in **11 days** and i havent opened the textbook once. looking for people who actually want to grind. ill bring the snacks

            #academics #study-group
            """,
            reactionCounts: [.like: 21, .hug: 3],
            comments: Comment.econStudyComments,
            imageUrl: "https://picsum.photos/id/431/800/500",
            imageAspectRatio: 1.6
        ),
        sample(
            author: "quinnm",
            tone: .blue,
            content: """
            # to whoever took my umbrella
            it was the only one i had. i hope it inverts on you at the worst possible moment. if you have a heart, its second floor by the vending machines

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
            content: "transferred in this semester and im still figuring out where anything is. 3 weeks in and i just found out there's a whole second cafeteria. also does anyone know how printing credits work bc i think im already in printing debt\n\n#transfer #campus-life",
            reactionCounts: [.hug: 24, .like: 18, .laugh: 9],
            comments: Comment.transferComments
        ),
        sample(
            author: "tylerb",
            tone: .red,
            content: "my roommate does dishes exactly once a month, always the day before his parents visit. otherwise the sink is a science experiment. i live with a man who treats a sponge like its cursed\n\n#venting #roommates",
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
            # to the person reading camus in the coffee line on monday
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
