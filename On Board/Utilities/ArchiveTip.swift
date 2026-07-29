//
//  ArchiveTip.swift
//  On Board
//
//  A single, deliberately-rare TipKit callout — the Archive lives inside the
//  "•••" menu with no other visual affordance, so it's genuinely easy to
//  never discover. Shows once, on the user's second app launch, only if
//  they've never opened the Archive; stops appearing on its own the moment
//  either condition is no longer true. Not a pattern to reach for often —
//  see CLAUDE.md's TipKit note before adding a second one.
//

import TipKit

struct ArchiveTip: Tip {
    static let appLaunchEvent = Event(id: "app-launch")

    @Parameter
    static var hasOpenedArchive: Bool = false

    var title: Text {
        Text("Missed something?")
    }

    var message: Text? {
        Text("Catch up on past weeks in the Archive.")
    }

    var rules: [Rule] {
        #Rule(Self.appLaunchEvent) { $0.donations.count >= 2 }
        #Rule(Self.$hasOpenedArchive) { $0 == false }
    }
}
