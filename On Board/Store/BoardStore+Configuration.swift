//
//  BoardStore+Configuration.swift
//  On Board
//
//  Session configuration and the DEV/mock-only board controls, split out of
//  BoardStore.swift. `resetForSignOut()` stays in the core file — it writes
//  `postProxies`, whose setter is deliberately `private(set)` there.
//  `devRolloverPrompts` (a static *stored* property, which extensions can't
//  hold) also stays in the core file.
//

import Foundation

extension BoardStore {

    // MARK: - Configuration

    func configure(configuration: AppConfiguration) {
        boardService = BoardServiceFactory.make(configuration: configuration)
        if boardService == nil {
            loadError = nil
        }
    }

    func setBoard(id: UUID, name: String?) {
        currentBoard = Board(id: id, name: name ?? currentBoard?.name ?? "On Board")
    }

    func clearLoadError() {
        loadError = nil
    }

    /// DEV/mock-only: shrink the active week so the clears-soon UI (red countdown,
    /// disabled new-post card, principal countdown) engages now and the weekly reset
    /// fires in `seconds`. Rebuilds the week with a near-future `endsAt`; ContentView's
    /// `.task(id: endsAt)` restarts on the change and drives the reset. No-op when live.
    func devSetCountdown(seconds: TimeInterval) {
        guard !isLive, let week = activeBoardWeek else { return }
        let shortened = BoardWeek(
            id: week.id,
            boardId: week.boardId,
            startsAt: week.startsAt,
            endsAt: Date.now.addingTimeInterval(seconds),
            status: week.status,
            archivedAt: week.archivedAt,
            promptClean: week.promptClean,
            promptProfane: week.promptProfane,
            postCount: week.postCount
        )
        activeBoardWeek = shortened
        boardWeeks = boardWeeks.map { $0.id == shortened.id ? shortened : $0 }
    }

    /// DEV/mock-only stand-in for the server-side weekly rollover.
    ///
    /// Mock builds have no `BoardService`, so `refresh(for:)` returns immediately and
    /// the reset animation used to land on the *exact same posts* — the take-down, the
    /// arrival, and every downstream "did the board actually change" behaviour were
    /// untestable offline. This performs the turnover in memory the way the backend
    /// does it: archive the outgoing week (its posts become read-only records reachable
    /// from the Archive), then open a fresh empty week with a new prompt.
    ///
    /// Returns false when there's nothing to roll over, so callers can fall through to
    /// the live refresh path instead of assuming a rollover happened.
    @discardableResult
    func devRollOverWeek() -> Bool {
        guard !isLive, let outgoing = activeBoardWeek else { return false }

        // The outgoing week ended when its clock ran out; a rollover triggered early by
        // the dev hook must not stamp an archivedAt in the future.
        let boundary = min(outgoing.endsAt, .now)
        let archived = BoardWeek(
            id: outgoing.id,
            boardId: outgoing.boardId,
            startsAt: outgoing.startsAt,
            endsAt: boundary,
            status: .archived,
            archivedAt: boundary,
            promptClean: outgoing.promptClean,
            promptProfane: outgoing.promptProfane,
            postCount: posts(for: outgoing).count
        )

        // Rotate deterministically off the number of weeks already on the board, so a
        // second rollover in one session doesn't repeat the prompt.
        let prompt = Self.devRolloverPrompts[boardWeeks.count % Self.devRolloverPrompts.count]
        let incoming = BoardWeek(
            id: UUID(),
            boardId: outgoing.boardId,
            startsAt: boundary,
            endsAt: boundary.addingTimeInterval(86_400 * 7),
            status: .active,
            promptClean: prompt.clean,
            promptProfane: prompt.profane,
            postCount: 0
        )

        // Everything from the outgoing week becomes a read-only record. The new week
        // starts genuinely empty — that empty state is the thing worth seeing.
        posts = posts.map { post in
            post.boardWeekId == outgoing.id
                ? post.assigning(boardWeekId: outgoing.id, isReadOnly: true)
                : post
        }
        boardWeeks = boardWeeks.map { $0.id == archived.id ? archived : $0 } + [incoming]
        activeBoardWeek = incoming
        rebuildCaches()
        return true
    }
}
