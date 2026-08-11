//
//  ContentView+Logic.swift
//  On Board
//
//  Navigation-path sanitizing, notification/deep-link pending routes, and the
//  weekly board-reset choreography — split out of ContentView.swift. All the
//  @State these mutate stays in the core file (widened to `internal` there,
//  since extensions in other files can't reach private members).
//

import SwiftUI

extension ContentView {

    func sanitizeNavigationPath() {
        var validPath = navigationPath
        while let last = validPath.last {
            var shouldPop = false
            switch last {
            case .post(let postID), .postFromProfile(let postID, _):
                if store.post(with: postID) == nil {
                    shouldPop = true
                }
            default:
                break
            }

            if shouldPop {
                validPath.removeLast()
            } else {
                break
            }
        }
        if validPath != navigationPath {
            navigationPath = validPath
        }
    }

    /// Navigates to the post a tapped notification pointed at, once it's
    /// actually in the store — pushing the route earlier would render an
    /// empty destination.
    func openPendingPostIfReady() {
        guard let postID = NotificationService.shared.pendingPostID else { return }
        if store.post(with: postID) != nil {
            NotificationService.shared.clearPendingPostID()
            showNewPost = false
            // Replace the path so the post opens even if the user was deep
            // in the Archive stack.
            navigationPath = [.post(postID)]
        } else if !store.isLoading, store.loadError == nil, store.activeBoardWeek != nil {
            // Feed is loaded but the post is gone (weekly reset, deleted, or wrong board) —
            // drop the stale route instead of retrying forever and alert the user.
            NotificationService.shared.clearPendingPostID()
            alertError = PresentableAlertError(
                message: "Post unavailable",
                recoverySuggestion: "This post could not be found or you don't have access to this board."
            )
        }
    }

    /// Navigates to the profile a shared profile link pointed at. Unlike posts,
    /// a profile with no posts this week never arrives via the feed refresh, so
    /// this fetches it directly instead of waiting on `store.isLoading`.
    func openPendingProfileIfReady() {
        guard let profileID = NotificationService.shared.pendingProfileID else { return }
        if let profile = store.profile(id: profileID) {
            NotificationService.shared.clearPendingProfileID()
            showNewPost = false
            navigationPath = [.profile(profile)]
            return
        }

        guard !isResolvingPendingProfile else { return }
        guard let boardService = store.boardService else {
            NotificationService.shared.clearPendingProfileID()
            alertError = PresentableAlertError(
                message: "Profile unavailable",
                recoverySuggestion: "This profile could not be found."
            )
            return
        }

        isResolvingPendingProfile = true
        Task {
            defer { isResolvingPendingProfile = false }
            if let fetched = try? await boardService.fetchProfiles(ids: [profileID]).first {
                store.upsertProfile(fetched)
                NotificationService.shared.clearPendingProfileID()
                showNewPost = false
                navigationPath = [.profile(fetched)]
            } else {
                NotificationService.shared.clearPendingProfileID()
                alertError = PresentableAlertError(
                    message: "Profile unavailable",
                    recoverySuggestion: "This profile could not be found or you don't have access to this board."
                )
            }
        }
    }

    /// Plays the take-down, swaps in the new week, and announces the arrival.
    ///
    /// Every rollover funnels through here — the scheduled `endsAt` timer, and (via
    /// `handleWeekChange`) a week that arrives on its own from the 45s poll or a
    /// foreground refresh. Before this, a poll that beat the timer swapped the entire
    /// board out with no animation and no explanation.
    func triggerBoardReset() async {
        // The timer and an incoming poll can both fire within the same second.
        guard !boardIsResetting else { return }
        boardIsResetting = true
        defer { boardIsResetting = false }

        // Only live-post destinations are invalidated by the wipe. PostDetailView
        // dismisses itself as well; this is the backstop for when its task was
        // suspended (covered by a sheet, app backgrounded across the boundary).
        navigationPath.removeAll(where: \.isLivePostDestination)

        // Quick snap to the top so the take-down only ever animates the cards the
        // user can actually see; everything below the fold is dropped by BoardFeedView.
        if reduceMotion {
            feedScrollPosition.scrollTo(edge: .top)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                feedScrollPosition.scrollTo(edge: .top)
            }
            try? await Task.sleep(for: .milliseconds(220))
        }

        // Bottom-to-top cascade: at most ~10 on-screen cards, each 0.06s apart, plus
        // the 0.45s per-card fade. Cap the wait to that window rather than the full
        // (possibly large) post count, which now never all animate.
        try? await Task.sleep(for: .seconds(10 * 0.06 + 0.45 + 0.15))

        let outgoingWeekID = store.activeBoardWeek?.id

        // Mock builds have no BoardService, so `refresh` is a no-op and the take-down
        // would land on the same posts it just swept away. Roll the week over in
        // memory instead; live builds fall through to the real fetch.
        if !store.devRollOverWeek() {
            await store.refresh(for: store.currentUserID)
        }

        // Our countdown runs on the device clock; the server archives on its own
        // schedule. If we hit zero first (clock skew, cron lag, a slow function),
        // the refresh above hands back the same expired week — the board is already
        // swept, so say what's happening and poll with backoff until the new week
        // actually exists. The expired phase keeps posting locked throughout.
        if store.activeBoardWeek?.id == outgoingWeekID {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                settingUpNewBoard = true
            }
            defer {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    settingUpNewBoard = false
                }
            }
            var retryDelay: Double = 2
            while store.activeBoardWeek?.id == outgoingWeekID {
                try? await Task.sleep(for: .seconds(retryDelay))
                // The 45s poll or a pull-to-refresh can land the new week first; its
                // endsAt change restarts the .task(id:) that owns us — stop cleanly
                // rather than double-fetching against the fresh board.
                if Task.isCancelled { break }
                await store.refresh(for: store.currentUserID)
                retryDelay = min(retryDelay * 2, 30)
            }
        }

        // Announce only a real turnover. On the cancelled path the week may still be
        // the outgoing one — whatever replaced this task owns what happens next.
        // Tracking lastKnownWeekID here as well as in handleWeekChange prevents the
        // observer firing a second, redundant announcement for this same week.
        if store.activeBoardWeek?.id != outgoingWeekID {
            lastKnownWeekID = store.activeBoardWeek?.id
            announceNewBoard()
        }
    }

    /// A new week appeared without us animating it in — the silent-swap path. The 45s
    /// poll, a pull-to-refresh, or the foreground refresh after the app was backgrounded
    /// across the boundary can all land one. Previously the board's entire contents
    /// changed underneath the user with no acknowledgement whatsoever.
    func handleWeekChange(to newID: UUID?) {
        defer { lastKnownWeekID = newID }
        // First observation of any week (cold launch, hydration) is not a rollover.
        guard let previous = lastKnownWeekID, let newID, previous != newID else { return }
        // triggerBoardReset owns its own announcement and has already run the take-down.
        guard !boardIsResetting else { return }
        announceNewBoard()
    }

    private func announceNewBoard() {
        withAnimation(reduceMotion ? nil : .snappy) {
            showBoardClearedToast = true
        }
    }
}
