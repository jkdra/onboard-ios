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
            avatarEmoji: "🌱",
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo, handle: "leokp", displayName: "Leo Park", bio: "design + caffeine.", avatarEmoji: "🎨"),
        Profile(id: SampleProfileID.aisha, handle: "aishap", displayName: "Aisha Patel", bio: "math nerd, sandwich enthusiast.", avatarEmoji: "📚"),
        Profile(id: SampleProfileID.daniel, handle: "danielr", displayName: "Daniel Reyes", bio: "ranks tims locations by line speed.", avatarEmoji: "☕️"),
        Profile(id: SampleProfileID.priya, handle: "priyas", displayName: "Priya Singh", bio: "always down for a study group.", avatarEmoji: "📝"),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee", bio: "the oat milk was MINE.", avatarEmoji: "🥛"),
        Profile(id: SampleProfileID.sara, handle: "saraa", displayName: "Sara Okafor", bio: "trails, parks, and snacks.", avatarEmoji: "🏞️"),
        Profile(id: SampleProfileID.jordan, handle: "jordank", displayName: "Jordan Kim", bio: "if my lab won't submit one more time...", avatarEmoji: "📡"),
        Profile(id: SampleProfileID.riley, handle: "rileyc", displayName: "Riley Chen", bio: "watching the squirrels carefully.", avatarEmoji: "🐿️"),
        Profile(id: SampleProfileID.quinn, handle: "quinnm", displayName: "Quinn Murphy", bio: "lost an umbrella, never recovered.", avatarEmoji: "☔️")
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

    static func lookup(id: UUID) -> Profile? {
        ProfileIndex(profiles: samples).profile(id: id)
    }
}
