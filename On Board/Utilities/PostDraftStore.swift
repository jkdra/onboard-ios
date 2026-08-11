//
//  PostDraftStore.swift
//  On Board
//
//  The composer's single draft slot. The hesitation loop is the real user
//  here: type, lose nerve, dismiss, come back. Dismissing with unsaved text
//  offers Save Draft / Discard (Mail's convention); the saved draft restores
//  on the next open.
//
//  ONE slot, this week only, by design:
//  * The slot is scoped to the board week — a draft about this board should
//    not haunt next Monday's.
//  * It expires when POSTING closes (the final-hour lockout,
//    `board_final_hour_lockout_hours`) — checked lazily at restore time, no
//    timer. One deadline for "you can no longer say this", shared with the
//    compose gate itself, and remote-tunable through the same config key.
//  * Multiple slots and cross-week carry-over are deliberately out of scope
//    today; if that ever changes, this becomes a keyed collection of slots
//    and the API (save/restore/clear per week) extends without callers
//    changing shape.
//
//  Plain UserDefaults, deliberately not CacheEnvelope: same reasoning as
//  remote config — the envelope is account-scoped board data cleared on
//  sign-out, while a half-typed thought is device-local scratch state.
//

import Foundation

struct PostDraftStore {
    var defaults: UserDefaults = .standard

    private static let contentKey = "compose.draft"
    private static let weekKey = "compose.draftWeekID"

    /// Persists the draft for the given week, overwriting the slot.
    func save(_ content: String, weekID: UUID?) {
        defaults.set(content, forKey: Self.contentKey)
        defaults.set(weekID?.uuidString ?? "", forKey: Self.weekKey)
    }

    /// Returns the stored draft if it belongs to `weekID` and posting is
    /// still open. A stale (previous-week) or expired (final-hour) draft is
    /// deleted on sight and nil is returned — expiry is enforced at read
    /// time, so no background cleanup can be missed.
    func restore(weekID: UUID?, allowsPosting: Bool) -> String? {
        guard let content = defaults.string(forKey: Self.contentKey),
              !content.isEmpty else { return nil }
        let storedWeek = defaults.string(forKey: Self.weekKey) ?? ""
        guard allowsPosting, let weekID, storedWeek == weekID.uuidString else {
            clear()
            return nil
        }
        return content
    }

    /// Whether a non-empty draft is currently stored (regardless of validity
    /// — callers wanting a valid draft use `restore`).
    var hasDraft: Bool {
        !(defaults.string(forKey: Self.contentKey) ?? "").isEmpty
    }

    func clear() {
        defaults.removeObject(forKey: Self.contentKey)
        defaults.removeObject(forKey: Self.weekKey)
    }
}
