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
            avatarUrl: "https://randomuser.me/api/portraits/women/44.jpg",
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo,    handle: "leokp",    displayName: "Leo Park",      bio: "design + caffeine.",                         avatarUrl: "https://randomuser.me/api/portraits/men/46.jpg"),
        Profile(id: SampleProfileID.aisha,  handle: "aishap",   displayName: "Aisha Patel",   bio: "math nerd, sandwich enthusiast.",             avatarUrl: "https://randomuser.me/api/portraits/women/65.jpg"),
        Profile(id: SampleProfileID.daniel, handle: "danielr",  displayName: "Daniel Reyes",  bio: "ranks tims locations by line speed.",         avatarUrl: "https://randomuser.me/api/portraits/men/33.jpg"),
        Profile(id: SampleProfileID.priya,  handle: "priyas",   displayName: "Priya Singh",   bio: "always down for a study group.",              avatarUrl: "https://randomuser.me/api/portraits/women/26.jpg"),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee",    bio: "the oat milk was MINE.",                      avatarUrl: "https://randomuser.me/api/portraits/men/55.jpg"),
        Profile(id: SampleProfileID.sara,   handle: "saraa",    displayName: "Sara Okafor",   bio: "trails, parks, and snacks.",                  avatarUrl: "https://randomuser.me/api/portraits/women/68.jpg"),
        Profile(id: SampleProfileID.jordan, handle: "jordank",  displayName: "Jordan Kim",    bio: "if my lab won't submit one more time...",     avatarUrl: "https://randomuser.me/api/portraits/men/64.jpg"),
        Profile(id: SampleProfileID.riley,  handle: "rileyc",   displayName: "Riley Chen",    bio: "watching the squirrels carefully.",           avatarUrl: "https://randomuser.me/api/portraits/women/47.jpg"),
        Profile(id: SampleProfileID.quinn,  handle: "quinnm",   displayName: "Quinn Murphy",  bio: "lost an umbrella, never recovered.",          avatarUrl: "https://randomuser.me/api/portraits/men/43.jpg"),
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

}
