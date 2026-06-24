//
//  Profile+Samples.swift
//  On Board
//

import Foundation

extension Profile {
    static let currentUser = Profile.samples[0]

    static let samples: [Profile] = [
        Profile(
            id: SampleProfileID.maya,
            handle: "maya.c",
            displayName: "Maya Chen",
            bio: "second year CS. perpetually one assignment behind.",
            avatarUrl: "https://i.pravatar.cc/256?img=47",
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo,    handle: "leokp",    displayName: "Leo Park",      bio: "design + caffeine.",                         avatarUrl: "https://i.pravatar.cc/256?img=11"),
        Profile(id: SampleProfileID.aisha,  handle: "aishap",   displayName: "Aisha Patel",   bio: "math nerd, sandwich enthusiast.",             avatarUrl: "https://i.pravatar.cc/256?img=49"),
        Profile(id: SampleProfileID.daniel, handle: "danielr",  displayName: "Daniel Reyes",  bio: "ranks tims locations by line speed.",         avatarUrl: "https://i.pravatar.cc/256?img=12"),
        Profile(id: SampleProfileID.priya,  handle: "priyas",   displayName: "Priya Singh",   bio: "always down for a study group.",              avatarUrl: "https://i.pravatar.cc/256?img=44"),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee",    bio: "the oat milk was MINE.",                      avatarUrl: "https://i.pravatar.cc/256?img=15"),
        Profile(id: SampleProfileID.sara,   handle: "saraa",    displayName: "Sara Okafor",   bio: "trails, parks, and snacks.",                  avatarUrl: "https://i.pravatar.cc/256?img=48"),
        Profile(id: SampleProfileID.jordan, handle: "jordank",  displayName: "Jordan Kim",    bio: "if my lab won't submit one more time...",     avatarUrl: "https://i.pravatar.cc/256?img=32"),
        Profile(id: SampleProfileID.riley,  handle: "rileyc",   displayName: "Riley Chen",    bio: "watching the squirrels carefully.",           avatarUrl: "https://i.pravatar.cc/256?img=45"),
        Profile(id: SampleProfileID.quinn,  handle: "quinnm",   displayName: "Quinn Murphy",  bio: "lost an umbrella, never recovered.",          avatarUrl: "https://i.pravatar.cc/256?img=18"),
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

}
