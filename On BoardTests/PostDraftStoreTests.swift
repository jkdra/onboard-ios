//
//  PostDraftStoreTests.swift
//  On BoardTests
//
//  The dismiss dialog itself can't be driven headlessly (no synthesized taps
//  under this Xcode), so the draft slot's rules are pinned here instead:
//  one slot, week-scoped, expired by the final-hour lockout at read time.
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct PostDraftStoreTests {

    private func makeStore() -> PostDraftStore {
        let suite = UserDefaults(suiteName: "PostDraftStoreTests-\(UUID().uuidString)")!
        return PostDraftStore(defaults: suite)
    }

    @Test func savedDraftRestoresForItsWeek() {
        let store = makeStore()
        let week = UUID()
        store.save("half a thought", weekID: week)
        #expect(store.restore(weekID: week, allowsPosting: true) == "half a thought")
        // Restoring is non-destructive — the slot survives until submit/discard.
        #expect(store.restore(weekID: week, allowsPosting: true) == "half a thought")
    }

    /// A draft about this board must not haunt next Monday's.
    @Test func staleWeekDraftIsDeletedOnSight() {
        let store = makeStore()
        store.save("last week's angst", weekID: UUID())
        #expect(store.restore(weekID: UUID(), allowsPosting: true) == nil)
        #expect(!store.hasDraft)
    }

    /// The "clears an hour before the board does" rule: once posting closes
    /// (final-hour lockout), the draft is gone.
    @Test func draftExpiresWhenPostingCloses() {
        let store = makeStore()
        let week = UUID()
        store.save("too late", weekID: week)
        #expect(store.restore(weekID: week, allowsPosting: false) == nil)
        #expect(!store.hasDraft)
    }

    @Test func savingOverwritesTheSingleSlot() {
        let store = makeStore()
        let week = UUID()
        store.save("first", weekID: week)
        store.save("second", weekID: week)
        #expect(store.restore(weekID: week, allowsPosting: true) == "second")
    }

    @Test func clearEmptiesTheSlot() {
        let store = makeStore()
        store.save("gone", weekID: UUID())
        store.clear()
        #expect(!store.hasDraft)
    }

    @Test func missingWeekNeverRestores() {
        let store = makeStore()
        store.save("orphan", weekID: nil)
        #expect(store.restore(weekID: nil, allowsPosting: true) == nil)
    }
}
