//
//  ReactionOverflowTests.swift
//  On BoardTests
//
//  The overflow slot's contract, which is mostly a stability contract.
//
//  THE RULE: counts are not an input to layout. The bar's shape depends on
//  config and on the viewer's own selection, never on how other people
//  reacted. An earlier version of this feature promoted a reaction to its own
//  pill once it had counts — which meant the third control was "+" on one
//  post, "laugh 12" on the next and "hug 19" after that, so it meant something
//  different every time it was tapped. `countsNeverChangeTheLayout` is the
//  regression test for that; if it ever fails, the bar has started adapting
//  its CONTROLS to content instead of adapting its content.
//

import Testing
@testable import On_Board

@MainActor
struct ReactionOverflowTests {

    private let all: [Reaction] = [.like, .dislike, .laugh, .hug]

    private func slots(
        selected: Reaction? = nil,
        enabled: [Reaction]? = nil,
        overflowEnabled: Bool = true
    ) -> ReactionBar.Slots {
        ReactionBar.slots(
            enabled: enabled ?? all,
            selected: selected,
            overflowEnabled: overflowEnabled
        )
    }

    // MARK: - The flag

    @Test func flagShipsInert() {
        #expect(FeatureFlag.reactionOverflow.compiledDefault == false)
    }

    @Test func offIsTodaysFlatBar() {
        let bar = slots(overflowEnabled: false)
        #expect(bar.permanent == all)
        #expect(!bar.hasOverflow)
        #expect(bar.total == 4)
    }

    // MARK: - Stability

    /// The whole point of the redesign: the strip is the same shape, with the
    /// same controls in the same order, on every post.
    @Test func theStripIsAlwaysThreeSlots() {
        for selection in [nil, .like, .dislike, .laugh, .hug] as [Reaction?] {
            let bar = slots(selected: selection)
            #expect(bar.permanent == [.like, .dislike])
            #expect(bar.hasOverflow)
            #expect(bar.total == 3)
        }
    }

    // NOTE: there is deliberately no `countsNeverChangeTheLayout` test. The
    // rule is enforced by `slots` not TAKING counts — a test could only call it
    // twice with the same arguments and compare, which asserts nothing and
    // would read as coverage the rule doesn't actually have. If someone ever
    // threads counts back into the signature, that is the review to catch, not
    // a test.

    // MARK: - The overflow slot's face

    @Test func plusUntilSomethingBehindItIsPicked() {
        #expect(slots(selected: nil).overflowFace == nil)
    }

    @Test func pickingAnOverflowReactionPutsItOnTheSlot() {
        #expect(slots(selected: .laugh).overflowFace == .laugh)
        #expect(slots(selected: .hug).overflowFace == .hug)
    }

    /// A permanent reaction has its own pill, so it must not also colonise the
    /// overflow slot — otherwise liking a post would silently hide the way in
    /// to laugh and hug.
    @Test func pickingAPermanentReactionLeavesThePlusAlone() {
        #expect(slots(selected: .like).overflowFace == nil)
        #expect(slots(selected: .dislike).overflowFace == nil)
    }

    /// Whatever the slot is wearing, the menu still offers everything —
    /// switching and deselecting both happen there.
    @Test func theMenuAlwaysOffersEveryOverflowReaction() {
        #expect(slots(selected: nil).overflow == [.laugh, .hug])
        #expect(slots(selected: .hug).overflow == [.laugh, .hug])
    }

    // MARK: - Composing with enabledReactions

    /// The split is positional, so reordering config changes which two are
    /// permanent — no reaction is special-cased in the bar.
    @Test func configOrderDecidesThePermanentTwo() {
        let bar = slots(enabled: [.like, .hug, .laugh, .dislike])
        #expect(bar.permanent == [.like, .hug])
        #expect(bar.overflow == [.laugh, .dislike])
    }

    /// A withdrawn reaction stays withdrawn — the menu must not resurrect
    /// something `enabled_reactions` deliberately removed.
    @Test func withdrawnReactionsNeverAppear() {
        let bar = slots(selected: .dislike, enabled: [.like, .laugh, .hug])
        #expect(!bar.overflow.contains(.dislike))
        #expect(bar.permanent == [.like, .laugh])
        // A selection that is no longer offered can't wear the slot either.
        #expect(bar.overflowFace == nil)
    }

    /// Two or fewer enabled reactions: nothing to overflow, so no third slot
    /// rather than an empty menu.
    @Test func aShortBarHasNoOverflowSlot() {
        let bar = slots(enabled: [.like, .dislike])
        #expect(bar.permanent == [.like, .dislike])
        #expect(!bar.hasOverflow)
        #expect(bar.total == 2)
    }

    // MARK: - The peek

    /// The peek may read counts — it changes only the slot's transient FACE,
    /// never the layout. These pin the relative threshold: dominant overflow
    /// reaction, ≥15% of the post's total, floors of 3 uses / 5 total.
    @Test func peekPicksTheDominantOverflowReaction() {
        let candidate = ReactionBar.peekCandidate(
            overflow: [.laugh, .hug],
            counts: [.like: 22, .dislike: 0, .laugh: 47, .hug: 6]
        )
        #expect(candidate == .laugh)
    }

    /// A permanent reaction dominating the post must not produce a peek —
    /// only what's BEHIND the menu is worth hinting at.
    @Test func peekIgnoresPermanentReactions() {
        let candidate = ReactionBar.peekCandidate(
            overflow: [.laugh, .hug],
            counts: [.like: 89, .laugh: 1, .hug: 0]
        )
        #expect(candidate == nil)
    }

    /// Relative, not absolute: 3 laughs is a signal on a quiet post…
    @Test func smallCountsPeekWhenTheShareIsReal() {
        let candidate = ReactionBar.peekCandidate(
            overflow: [.laugh, .hug],
            counts: [.like: 4, .laugh: 3]
        )
        #expect(candidate == .laugh)
    }

    /// …and 3 laughs is noise on a loud one.
    @Test func smallShareDoesNotPeekOnALoudPost() {
        let candidate = ReactionBar.peekCandidate(
            overflow: [.laugh, .hug],
            counts: [.like: 200, .laugh: 3]
        )
        #expect(candidate == nil)
    }

    @Test func quietPostsNeverPeek() {
        let candidate = ReactionBar.peekCandidate(
            overflow: [.laugh, .hug],
            counts: [.laugh: 2]
        )
        #expect(candidate == nil)
    }
}
