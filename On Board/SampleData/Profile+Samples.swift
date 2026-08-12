//
//  Profile+Samples.swift
//  On Board
//
//  Deliberately NO avatarUrl on any sample profile: these render through
//  AvatarView's own monogram fallback, which the app owns outright.
//
//  These used to point at randomuser.me, whose portraits come (via UI
//  Faces) from Greg Peverill-Conti's "1000 faces" project under
//  CC BY-NC-SA 2.0 — NonCommercial forbids an App Store listing, and
//  neither attribution nor ShareAlike was satisfied. They're also
//  photographs of real, identifiable people, which needs a model release
//  before appearing in marketing screenshots. Don't reintroduce a remote
//  avatar host; if sample avatars are ever wanted, bundle art we own.
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
            birthday: "2003-05-14",
            showBirthday: true,
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo,    handle: "leokp",    displayName: "Leo Park",       bio: "design + caffeine.", birthday: "2002-11-02", showBirthday: false),
        Profile(id: SampleProfileID.layla,  handle: "laylah",   displayName: "Layla Haddad",   bio: "mech eng. building things that occasionally don't catch fire."),
        Profile(id: SampleProfileID.daniel, handle: "danielr",  displayName: "Daniel Reyes",   bio: "ranks campus coffee by line speed."),
        Profile(id: SampleProfileID.priya,  handle: "priyas",   displayName: "Priya Singh",    bio: "always down for a study group."),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee",     bio: "the oat milk was MINE."),
        Profile(id: SampleProfileID.sara,   handle: "saraa",    displayName: "Sara Okafor",    bio: "trails, parks, and snacks."),
        Profile(id: SampleProfileID.jordan, handle: "jordank",  displayName: "Jordan Kim",     bio: "if my lab won't submit one more time..."),
        Profile(id: SampleProfileID.riley,  handle: "rileyc",   displayName: "Riley Chen",     bio: "watching the squirrels carefully."),
        Profile(id: SampleProfileID.quinn,  handle: "quinnm",   displayName: "Quinn Murphy",   bio: "lost an umbrella, never recovered."),
        Profile(id: SampleProfileID.kevin,  handle: "kevinz",   displayName: "Kevin Zhang",    bio: "finance major, day-trading my meal plan money. don't tell my mom."),
        Profile(id: SampleProfileID.ben,    handle: "benw",     displayName: "Ben Whitman",    bio: "transferred in this semester, still lost 70% of the time."),
        Profile(id: SampleProfileID.nora,   handle: "noraf",    displayName: "Nora Fitzgerald",bio: "here for the vibes and the video games."),
        Profile(id: SampleProfileID.zainab, handle: "zainabr",  displayName: "Zainab Rahman",  bio: "pre-med, running on coffee and spite."),
        Profile(id: SampleProfileID.tyler,  handle: "tylerb",   displayName: "Tyler Brooks",   bio: "professional roommate complainer."),
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

}
