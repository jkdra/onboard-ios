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
            birthday: "2003-05-14",
            showBirthday: true,
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo,    handle: "leokp",    displayName: "Leo Park",       bio: "design + caffeine.",                                    avatarUrl: "https://randomuser.me/api/portraits/men/4.jpg", birthday: "2002-11-02", showBirthday: false),
        Profile(id: SampleProfileID.layla,  handle: "laylah",   displayName: "Layla Haddad",   bio: "mech eng. building things that occasionally don't catch fire.", avatarUrl: "https://randomuser.me/api/portraits/women/40.jpg"),
        Profile(id: SampleProfileID.daniel, handle: "danielr",  displayName: "Daniel Reyes",   bio: "ranks tims locations by line speed.",                   avatarUrl: "https://randomuser.me/api/portraits/men/7.jpg"),
        Profile(id: SampleProfileID.priya,  handle: "priyas",   displayName: "Priya Singh",    bio: "always down for a study group.",                        avatarUrl: "https://randomuser.me/api/portraits/women/88.jpg"),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee",     bio: "the oat milk was MINE.",                                 avatarUrl: "https://randomuser.me/api/portraits/men/26.jpg"),
        Profile(id: SampleProfileID.sara,   handle: "saraa",    displayName: "Sara Okafor",    bio: "trails, parks, and snacks.",                             avatarUrl: "https://randomuser.me/api/portraits/women/6.jpg"),
        Profile(id: SampleProfileID.jordan, handle: "jordank",  displayName: "Jordan Kim",     bio: "if my lab won't submit one more time...",               avatarUrl: "https://randomuser.me/api/portraits/men/90.jpg"),
        Profile(id: SampleProfileID.riley,  handle: "rileyc",   displayName: "Riley Chen",     bio: "watching the squirrels carefully.",                     avatarUrl: "https://randomuser.me/api/portraits/women/35.jpg"),
        Profile(id: SampleProfileID.quinn,  handle: "quinnm",   displayName: "Quinn Murphy",   bio: "lost an umbrella, never recovered.",                    avatarUrl: "https://randomuser.me/api/portraits/men/43.jpg"),
        Profile(id: SampleProfileID.kevin,  handle: "kevinz",   displayName: "Kevin Zhang",    bio: "finance major, day-trading my meal plan money. don't tell my mom.", avatarUrl: "https://randomuser.me/api/portraits/men/92.jpg"),
        Profile(id: SampleProfileID.ben,    handle: "benw",     displayName: "Ben Whitman",    bio: "transferred in this semester, still lost 70% of the time.", avatarUrl: "https://randomuser.me/api/portraits/men/10.jpg"),
        Profile(id: SampleProfileID.nora,   handle: "noraf",    displayName: "Nora Fitzgerald",bio: "here for the vibes and the video games.",               avatarUrl: "https://randomuser.me/api/portraits/women/74.jpg"),
        Profile(id: SampleProfileID.zainab, handle: "zainabr",  displayName: "Zainab Rahman",  bio: "pre-med, running on coffee and spite.",                 avatarUrl: "https://randomuser.me/api/portraits/women/18.jpg"),
        Profile(id: SampleProfileID.tyler,  handle: "tylerb",   displayName: "Tyler Brooks",   bio: "professional roommate complainer.",                     avatarUrl: "https://randomuser.me/api/portraits/men/71.jpg"),
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

}
