//
//  ContentView.swift
//  On Board
//
//  Home feed for the active board week.
//

import SwiftUI
import TipKit

struct ContentView: View {

    @Environment(BoardStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(RemoteConfigStore.self) private var remoteConfig
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @State private var navigationPath: [BoardRoute] = []
    @State private var archiveTip = ArchiveTip()
    @State private var showNewPost = false
    @State private var boardIsResetting = false
    @State private var pulseLowOpacity = false
    @State private var alertError: PresentableAlertError?
    @State private var isResolvingPendingProfile = false
    @State private var showWelcomeReplay = false
    /// Fires the once-a-year birthday celebration (fireworks + the countdown
    /// card's greeting) when the current user's birthday is today.
    @State private var birthdayCelebrating = false
    /// True while the in-feed new-post card is at least partly on screen. When it
    /// scrolls away (and posting is still open), the bottom-bar compose button appears.
    @State private var newPostCardVisible = true
    /// Drives the programmatic snap-to-top at the start of the weekly reset.
    @State private var feedScrollPosition = ScrollPosition()
    /// Announces the turnover. Without it the board's entire contents changed with no
    /// acknowledgement — a post you were reading would just evaporate.
    @State private var showBoardClearedToast = false
    /// True while the take-down has finished but the server hasn't produced the new
    /// week yet (device clock ahead of the server's rollover). The board is already
    /// swept, so this drives the "Setting up this week's board…" indicator.
    @State private var settingUpNewBoard = false
    /// Last week id this view has seen, so a week arriving on its own (poll, foreground
    /// refresh) can be told apart from the one we rolled over ourselves.
    @State private var lastKnownWeekID: UUID?
    @Namespace private var cardNamespace

    /// nil when `FeatureFlag.zoomTransition` is off, which disables the zoom at
    /// both ends at once: sources stop registering (the
    /// `matchedTransitionSource(id:in:)` overload no-ops on a nil namespace) and
    /// destinations fall back to a plain push. Disabling only one end would leave
    /// the destination resolving no source rect and collapsing the card on pop.
    ///
    /// CLAUDE.md documents four separate landmine categories around this
    /// transition, and the plain-push fallback is trivially correct — which is
    /// why this is the highest-value kill switch in the app.
    private var activeCardNamespace: Namespace.ID? {
        remoteConfig.isEnabled(.zoomTransition, for: auth.session?.userId) ? cardNamespace : nil
    }

    /// DEV/mock-only: the in-feed dev scratch block (Signal Lost preview, tint/aspect
    /// pickers) fills roughly 1.5 screens above the masonry, so a snap-to-top during a
    /// UI-test walkthrough frames the controls instead of the feed. Pass
    /// `-dev.hideDevBlock` to suppress it and see the real board.
    private static let hidesDevBlock =
        ProcessInfo.processInfo.arguments.contains("-dev.hideDevBlock")

    /// DEV/mock-only: `-dev.openPostIndex <n>` pushes the nth feed post's
    /// detail on appear. Exists because synthesized taps are broken under the
    /// current Xcode's XCUITest (see ReactionBarInsetUITests) and headless
    /// walkthroughs still need to reach PostDetailView.
    private static let devOpenPostIndex: Int? =
        ProcessInfo.processInfo.arguments.contains("-dev.openPostIndex")
            ? UserDefaults.standard.integer(forKey: "dev.openPostIndex") : nil

    private var clearingSoon: Bool {
        BoardSchedule.isClearingSoon(weekEnd: store.activeBoardWeek?.endsAt,
                                     thresholds: remoteConfig.config.boardThresholds)
    }

    /// True only while the feed actually contains an *enabled* compose card — i.e.
    /// an interactive week outside the final hour. Gates the bottom-bar button so it
    /// never appears on archived weeks or once posting has closed.
    private var postingEnabled: Bool {
        store.feedItems.contains {
            if case .newPost(let isEnabled, _) = $0 { return isEnabled }
            return false
        }
    }

    /// Shows the bottom-bar compose button once the in-feed card is scrolled away.
    private var showsBottomBarNewPost: Bool {
        postingEnabled && !newPostCardVisible
    }

    /// iOS 26 gives `.bottomBar` a liquid-glass background the button rides on; on
    /// earlier versions we hide that background and let the button wear its own material.
    private var isIOS26OrLater: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            thisWeekFeed
                .navigationDestination(for: BoardRoute.self, destination: routeDestination)
                .navigationBarBackButtonHidden(true)
                .sheet(isPresented: $showNewPost) { NewPostView() }
                .boardErrorHandling(alertError: $alertError, suppressWhenBoardMissing: true)
                .presentableErrorAlert(error: $alertError)
        }
        // Applied outside the NavigationStack so pushed destinations (ProfileView,
        // ArchivedWeekView) inherit it too. Every BoardFeedView beneath this point
        // registers its zoom sources in the namespace routeDestination zooms from.
        .environment(\.cardNamespace, activeCardNamespace)
        // The config-driven environment values (glass, photo attachments,
        // reactions, field limits…) are injected in RootView, not here — this
        // view is a *sibling* of OnboardingCoordinator, and injections made
        // here never reached the onboarding subtree (its profile step
        // silently validated against the compiled limits).
        // Notification deep-link: fires on warm relaunch (post already cached),
        // on a tap while the app is alive, and after the cold-launch fetch
        // settles (isLoading flips false) — whichever happens first.
        .onAppear { openPendingPostIfReady() }
        .task {
            // DEV: `-dev.openComposer` opens the compose sheet on launch —
            // headless composer screenshots, same rationale as openPostIndex.
            // Deferred rather than set in `onAppear`: flipping it during the
            // same appear pass that installs the `.sheet` is swallowed, and
            // the arg silently did nothing.
            guard ProcessInfo.processInfo.arguments.contains("-dev.openComposer") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            showNewPost = true
        }
        .onAppear {
            guard let index = Self.devOpenPostIndex,
                  store.posts.indices.contains(index),
                  navigationPath.isEmpty else { return }
            navigationPath.append(.post(store.posts[index].id))
        }
        .onAppear { openPendingProfileIfReady() }
        .onChange(of: NotificationService.shared.pendingPostID) { _, _ in
            openPendingPostIfReady()
        }
        .onChange(of: NotificationService.shared.pendingProfileID) { _, _ in
            openPendingProfileIfReady()
        }
        .onChange(of: store.isLoading) { _, loading in
            if !loading { openPendingPostIfReady() }
        }
        .onChange(of: store.blockedUserIDs) { _, _ in
            sanitizeNavigationPath()
        }
    }
    
    private func sanitizeNavigationPath() {
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
    private func openPendingPostIfReady() {
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
    private func openPendingProfileIfReady() {
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

    private var thisWeekFeed: some View {
        let feedItems = store.feedItems
        return ZStack {
            ScrollView {
                if onboarding.supportsDevAdmission, !Self.hidesDevBlock {
                    DevFeedScratchBlock(showWelcomeReplay: $showWelcomeReplay)
                }

                BoardFeedView(
                    items: feedItems,
                    onNewPost: { showNewPost = true },
                    isResetting: boardIsResetting,
                    celebrateBirthday: birthdayCelebrating,
                    onNewPostCardVisibilityChanged: { visible in
                        guard newPostCardVisible != visible else { return }
                        withAnimation(reduceMotion ? nil : .snappy) {
                            newPostCardVisible = visible
                        }
                    }
                )

                if store.isLive, !store.isLoading, !store.hasFeedPosts {
                    emptyFeedState
                }
            }
            .scrollPosition($feedScrollPosition)

            if store.isLoading, store.posts.isEmpty {
                // Ghost masonry in the real card geometry — reads as "the board
                // is coming" instead of a generic spinner. Scroll stays behind
                // it so the countdown/new-post cards keep their positions.
                ScrollView {
                    FeedSkeletonView()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if settingUpNewBoard {
                // The old board is swept and the new week hasn't landed yet. The feed
                // behind this is intentionally empty (boardIsResetting keeps it so).
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Setting up this week's board…")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .fireworks(isActive: birthdayCelebrating)
        .task(id: store.currentUser?.id) {
            guard let user = store.currentUser,
                  BirthdayCelebration.isToday(user.birthday),
                  !BirthdayCelebration.feedShown(for: user.id) else { return }
            BirthdayCelebration.markFeedShown(for: user.id)
            birthdayCelebrating = true
        }
        .background {
            if clearingSoon {
                LinearGradient(
                    colors: [
                        Color.red.opacity(pulseLowOpacity ? 0.08 : 0.22),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(
                        .easeInOut(duration: 2.5)
                            .repeatForever(autoreverses: true)
                    ) { pulseLowOpacity = true }
                }
            } else {
                LinearGradient(
                    colors: [
                        Color.gray.opacity(scheme == .light ? 0.25 : 0.20),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .refreshable {
            await store.refresh(for: store.currentUserID)
        }
        .fullScreenCover(isPresented: $showWelcomeReplay) {
            WelcomeOnBoardView(boardName: onboarding.status?.boardName)
        }
        .navigationTitle("This Week")
        // The large title only collapses to the compact bar (where .principal
        // content actually renders) once the user scrolls past it — so simply
        // mounting the countdown ToolbarItem wasn't enough to show it "at all
        // times": at the top of the feed the large "This Week" title was still
        // covering it, countdown card visible or not. Forcing .inline for the
        // whole clearing-soon window skips the large title entirely so the
        // countdown is visible in the nav bar from the moment the window opens.
        .navigationBarTitleDisplayMode(clearingSoon ? .inline : .automatic)
        .task {
            // No realtime subscription for reactions/posts (removed — the app is
            // weekly-cadence, not a live chat, so instant cross-user updates aren't
            // worth the always-on connection). This silent poll is the replacement:
            // pull-to-refresh and foreground-refresh cover the rest.
            //
            // This `.task` lives on the NavigationStack's *root* content, which SwiftUI
            // keeps mounted — and this loop running — even while Archive/Settings/a post
            // is pushed on top. Gating the actual refresh on `navigationPath.isEmpty`
            // stops it from silently hitting the network every 45s while the user isn't
            // even looking at the feed.
            while !Task.isCancelled {
                // Server-tunable (`feed_poll_seconds`, default 45): a direct
                // battery/freshness/DB-load dial that can be widened without a
                // release if Supabase load spikes.
                try? await Task.sleep(for: .seconds(remoteConfig.config.feedPollSeconds))
                guard !Task.isCancelled else { break }
                guard navigationPath.isEmpty else { continue }
                await store.refresh(for: store.currentUserID)
            }
        }
        .task {
            // DEV/mock only: `-dev.clearAfter <seconds>` shrinks the week on a delay
            // rather than on a menu tap. The menu is unreachable once a sheet is up, so
            // this is the only way to drive a reset that lands while the composer is
            // open with a typed draft — the case that silently destroyed user work.
            let delay = UserDefaults.standard.double(forKey: "dev.clearAfter")
            guard delay > 0, onboarding.supportsDevAdmission else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            store.devSetCountdown(seconds: 5)
        }
        .task(id: store.activeBoardWeek?.endsAt) {
            guard let endsAt = store.activeBoardWeek?.endsAt else { return }
            // Already past the deadline (relaunched onto a stale week, or the sleep
            // below was suspended while backgrounded): roll over immediately rather
            // than leaving the board sitting expired with no scheduled trigger.
            if endsAt > .now {
                try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
            }
            await triggerBoardReset()
        }
        .onChange(of: store.activeBoardWeek?.id, initial: true) { _, newID in
            handleWeekChange(to: newID)
        }
        .toast(
            isPresented: $showBoardClearedToast,
            message: "The board cleared. This is a new week.",
            icon: "sparkles"
        )
        // Pre-26: hide the bar chrome so only the button's own circular material
        // shows. On 26+ we leave it automatic so the button rides the liquid glass.
        .toolbarBackground(isIOS26OrLater ? .automatic : .hidden, for: .bottomBar)
        .toolbar {
            // Shown for the whole clearing-soon window regardless of scroll position —
            // simpler than reacting to the countdown card's own on-screen state, and
            // it sidesteps a real defect that approach had: toggling a ToolbarItem's
            // *presence* on every scroll forces UIKit to reassign
            // UINavigationItem.titleView, which runs its own layout pass and visibly
            // slides the new title in from the side. SwiftUI's .transition has no
            // authority over that — it only animates content within an already-stable
            // item. Mounting this once per clearing-soon window (not per scroll) keeps
            // it firmly inside SwiftUI's own animation system.
            if clearingSoon {
                ToolbarItem(placement: .principal) {
                    ClearingSoonPrincipal(weekEnd: store.activeBoardWeek?.endsAt)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // Archive's own entry point — the tip's condition
                        // goes false the moment this is set, so it won't
                        // show again after this first visit.
                        ArchiveTip.hasOpenedArchive = true
                        navigationPath.append(BoardRoute.archive)
                    } label: {
                        Label("Archive", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    Button {
                        navigationPath.append(BoardRoute.settings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    if onboarding.supportsDevAdmission {
                        // DEV/mock only: shrink the week so the clears-soon UI + reset
                        // fire in ~10s. In the menu (not the feed) so it's always
                        // tappable — a feed button here sits under the bottom toolbar.
                        Button {
                            store.devSetCountdown(seconds: 10)
                        } label: {
                            Label("Clear board in 10s [DEV]", systemImage: "clock.badge.exclamationmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").fontWeight(.semibold)
                }
                .accessibilityLabel("More")
                // "Archive" itself is invisible until this menu is open, so
                // the tip has to point at the menu's own trigger instead.
                .popoverTip(archiveTip)
            }
            // Mounted for as long as posting could ever be relevant (the whole
            // interactive week), not just while the in-feed card is off screen.
            // `.bottomBar` items bridge to UIToolbar.items — an array — so
            // conditionally including/excluding one on every scroll (the old
            // `showsBottomBarNewPost` gate) churns that array's count on every
            // frame the card's visibility toggles, the same ToolbarItem-presence
            // anti-pattern that caused the nav-principal slide bug above. Keeping
            // the item mounted and fading its content via `showsBottomBarNewPost`
            // instead keeps the toolbar's item count stable while scrolling.
            // iOS 26+ only: there the button rides the bottom bar's liquid
            // glass and looks native. The pre-26 fallback (a hand-rolled
            // material circle) never sat right against the masonry — on 18–25
            // the in-feed compose card is the sole entry point.
            if postingEnabled, isIOS26OrLater {
                ToolbarItem(placement: .bottomBar) {
                    bottomBarNewPostButton
                }
            }
        }
    }

    /// Icon-only compose button surfaced in the bottom bar once the in-feed card
    /// scrolls away. iOS 26+ only (gated at the ToolbarItem) — the toolbar's
    /// liquid glass is what makes it look native, and no pre-26 approximation
    /// of that material read as anything but off.
    private var bottomBarNewPostButton: some View {
        Button {
            showNewPost = true
        } label: {
            Label("New post", systemImage: "plus")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
        }
        .accessibilityLabel("New post")
        .accessibilityHidden(!showsBottomBarNewPost)
        .allowsHitTesting(showsBottomBarNewPost)
        .opacity(showsBottomBarNewPost ? 1 : 0)
    }

    @ViewBuilder
    private func routeDestination(for route: BoardRoute) -> some View {
        switch route {
        case .archive:
            ArchiveView()
        case .archivedWeek(let week):
            ArchivedWeekView(week: week)
        // sourceID is the route itself, matching the id the pushing card registered.
        // Keying on the bare postID would be ambiguous while a ProfileView showing the
        // same post sits on the stack above the feed.
        case .post(let postID):
            if let post = store.post(with: postID) {
                PostDetailView(post: post)
                    .environment(store)
                    .zoomTransition(sourceID: route, in: activeCardNamespace)
            }
        case .postFromProfile(let postID, let profileID):
            if let post = store.post(with: postID) {
                PostDetailView(post: post)
                    .environment(store)
                    .environment(\.originatingProfileID, profileID)
                    .zoomTransition(sourceID: route, in: activeCardNamespace)
            }
        case .profile(let profile):
            ProfileView(profile: profile, presentation: .navigation)
        case .settings:
            SettingsView()
                // Reasserted here (not just on ContentView() at the RootView
                // call site) so Settings reactively tracks `appearance`
                // changes instead of only reflecting whatever the scheme was
                // when this destination was pushed.
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// Plays the take-down, swaps in the new week, and announces the arrival.
    ///
    /// Every rollover funnels through here — the scheduled `endsAt` timer, and (via
    /// `handleWeekChange`) a week that arrives on its own from the 45s poll or a
    /// foreground refresh. Before this, a poll that beat the timer swapped the entire
    /// board out with no animation and no explanation.
    private func triggerBoardReset() async {
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
    private func handleWeekChange(to newID: UUID?) {
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

    private var emptyFeedState: some View {
        Group {
            if store.activeBoardWeek != nil {
                // Board loaded, no posts yet
                VStack(spacing: 12) {
                    Text("Nothing posted yet")
                        .fontStyle(.headline)
                    Text("Be the first to pin something to this week's board.")
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Board didn't load — show retry
                VStack(spacing: 16) {
                    Text("Couldn't load board")
                        .fontStyle(.headline)
                    
                    if let errorMsg = store.loadError {
                        Text(errorMsg)
                            .fontStyle(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Pull down to try again.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Retry") {
                        Task { await store.refresh(for: store.currentUserID) }
                    }
                    .buttonStyle(.boardPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 24)
    }
}

#Preview("Mock Feed") {
    ContentView()
        .environment(BoardStore.previewBoard())
        .environment(AuthStore(service: MockAuthService()))
        .environment(RemoteConfigStore())
}

#Preview("Live Feed") {
    LiveFeedPreview()
        .environment(RemoteConfigStore())
}

private struct LiveFeedPreview: View {
    @State private var auth: AuthStore
    @State private var onboarding: OnboardingStore
    @State private var store: BoardStore

    init() {
        let a = AuthStore(service: AuthServiceFactory.make())
        let n = NetworkMonitor()
        _auth = State(wrappedValue: a)
        _onboarding = State(wrappedValue: OnboardingStore(
            service: OnboardingServiceFactory.make(),
            auth: a,
            network: n
        ))
        _store = State(wrappedValue: BoardStore(
            boardService: BoardServiceFactory.make(configuration: AppConfiguration.current)
        ))
    }

    @State private var didRestore = false

    var body: some View {
        if AppConfiguration.current.isSupabaseConfigured {
            Group {
                if !didRestore {
                    ProgressView("Restoring session…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.session == nil {
                    ContentUnavailableView(
                        "Sign in first",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Run the app, sign in, then reopen this preview.")
                    )
                } else {
                    ContentView()
                        .environment(store)
                        .environment(auth)
                }
            }
            .task {
                await auth.restoreSession()
                didRestore = true
                guard let session = auth.session else { return }
                store.setCurrentUser(id: session.userId)
                await onboarding.refreshIfOnline()
                if let boardId = onboarding.status?.boardId {
                    store.setBoard(id: boardId, name: onboarding.status?.boardName)
                }
                await store.refresh(for: session.userId)
            }
        } else {
            ContentUnavailableView(
                "Supabase not configured",
                systemImage: "key.slash",
                description: Text("Add Secrets.xcconfig with SUPABASE_URL and SUPABASE_ANON_KEY.")
            )
        }
    }
}
