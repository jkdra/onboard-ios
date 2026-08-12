//
//  Profile+Samples.swift
//  On Board
//
//  Sample avatars come from DiceBear's "notionists" style, which is
//  CC0 1.0 — public domain, commercial use, no attribution, and nobody
//  real is depicted, so no model release is needed. The line-art register
//  also happens to be the brand's. Seeded by handle, so a given person
//  looks the same everywhere without us storing anything.
//
//  This URL is only ever hit in mock/sample mode; real profiles carry
//  Supabase avatar URLs, so no shipped user request reaches DiceBear.
//
//  These previously pointed at randomuser.me, whose portraits come (via
//  UI Faces) from Greg Peverill-Conti's "1000 faces" project under
//  CC BY-NC-SA 2.0 — NonCommercial forbids an App Store listing, and
//  neither attribution nor ShareAlike was satisfied. They were also
//  photographs of real, identifiable people, which needs a model release
//  before appearing in marketing screenshots. Any replacement must clear
//  BOTH bars: a commercial-use licence AND no real person depicted.
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
            avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=maya.c&size=240&backgroundColor=f2f2f2",
            birthday: "2003-05-14",
            showBirthday: true,
            joinedAt: Date(timeIntervalSince1970: 1_725_148_800)
        ),
        Profile(id: SampleProfileID.leo,    handle: "leokp",    displayName: "Leo Park",       bio: "design + caffeine.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=leokp&size=240&backgroundColor=f2f2f2", birthday: "2002-11-02", showBirthday: false),
        Profile(id: SampleProfileID.layla,  handle: "laylah",   displayName: "Layla Haddad",   bio: "mech eng. building things that occasionally don't catch fire.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=laylah&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.daniel, handle: "danielr",  displayName: "Daniel Reyes",   bio: "ranks campus coffee by line speed.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=danielr&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.priya,  handle: "priyas",   displayName: "Priya Singh",    bio: "always down for a study group.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=priyas&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.marcus, handle: "marcus.l", displayName: "Marcus Lee",     bio: "the oat milk was MINE.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=marcus.l&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.sara,   handle: "saraa",    displayName: "Sara Okafor",    bio: "trails, parks, and snacks.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=saraa&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.jordan, handle: "jordank",  displayName: "Jordan Kim",     bio: "if my lab won't submit one more time...", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=jordank&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.riley,  handle: "rileyc",   displayName: "Riley Chen",     bio: "watching the squirrels carefully.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=rileyc&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.quinn,  handle: "quinnm",   displayName: "Quinn Murphy",   bio: "lost an umbrella, never recovered.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=quinnm&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.kevin,  handle: "kevinz",   displayName: "Kevin Zhang",    bio: "finance major, day-trading my meal plan money. don't tell my mom.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=kevinz&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.ben,    handle: "benw",     displayName: "Ben Whitman",    bio: "transferred in this semester, still lost 70% of the time.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=benw&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.nora,   handle: "noraf",    displayName: "Nora Fitzgerald",bio: "here for the vibes and the video games.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=noraf&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.zainab, handle: "zainabr",  displayName: "Zainab Rahman",  bio: "pre-med, running on coffee and spite.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=zainabr&size=240&backgroundColor=f2f2f2"),
        Profile(id: SampleProfileID.tyler,  handle: "tylerb",   displayName: "Tyler Brooks",   bio: "professional roommate complainer.", avatarUrl: "https://api.dicebear.com/9.x/notionists/png?seed=tylerb&size=240&backgroundColor=f2f2f2"),
    ]

    static func lookup(handle: String) -> Profile? {
        ProfileIndex(profiles: samples).profile(handle: handle)
    }

}
