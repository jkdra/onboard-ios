//
//  ContentView+Views.swift
//  On Board
//
//  The feed screen's main content, route destinations, and empty state —
//  split out of ContentView.swift. The @Namespace and all @State stay in the
//  core file (widened to `internal` there, since extensions in other files
//  can't reach private members).
//

import SwiftUI
import TipKit

extension ContentView {

    var thisWeekFeed: some View {
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

                // Not gated on `store.isLive`: a cleared mock board is the
                // same fresh-Monday moment (and the only way to demo/verify
                // this state headlessly). `!isLoading` still prevents the
                // initial-load flash.
                if !store.isLoading, !store.hasFeedPosts {
                    emptyFeedState
                }
            }
            // Bottom-bar clearance for the scroll CONTENT (not BoardFeedView):
            // on BoardFeedView it wedged 64pt of dead band between an empty
            // board's cards and the empty-state block below them.
            .safeAreaPadding(.bottom, 64)
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
            // …and not on an EMPTY board: iOS 26 re-hosts the toolbar label
            // inside its liquid-glass platter, where the button's opacity
            // gate doesn't reach — so the "hidden" + rendered fully visible
            // next to the dashed compose card every fresh Monday. With no
            // posts there's nothing to scroll the compose card away behind,
            // so the item has no job; hasFeedPosts changes on post-create /
            // reset, not per scroll frame, so this doesn't churn the
            // toolbar-item array the way the old per-scroll gate did.
            if postingEnabled, isIOS26OrLater, store.hasFeedPosts {
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
    func routeDestination(for route: BoardRoute) -> some View {
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

    private var emptyFeedState: some View {
        Group {
            if store.activeBoardWeek != nil {
                // Board loaded, no posts yet — the fresh-Monday moment is The
                // Host's canvas (one of his few budgeted surfaces: empty
                // states earn a mascot; composing and reading never do). The
                // figure is the vector rig, static — no looping animation,
                // per the repeatForever/UI-test rule.
                // ContentUnavailableView's shape, in the brand's own art:
                // secondary-weight mark, short title, one-line description.
                // The compose card above is the screen's actual call to
                // action, so this block only names the state.
                //
                // The Host is STRESSED here, not happy — an empty board is
                // not a win, and a grinning mascot over "nobody has posted"
                // reads as tone-deaf. Transparent body + `.secondary` line
                // color puts him at the description's weight (Apple's
                // ContentUnavailableView image sits at secondary too), which
                // also drops the scheme-inversion: `.secondary` adapts.
                VStack(spacing: 24) {
                    HostFigure(
                        eye: .sad,
                        article: .sweat,
                        lineColor: .secondary,
                        bodyFill: .transparent
                    )
                    .frame(width: 56)
                    // Canvas resolves `Color.secondary` to secondaryLabel's
                    // RGB but DROPS its 0.6 alpha (a GraphicsContext fill
                    // takes a concrete color, not a hierarchical style), so
                    // he rendered at full strength — obvious in dark mode,
                    // where he outshone his own caption. Reapplying the
                    // alpha as a view modifier lands him exactly at the
                    // description's weight in both schemes.
                    .opacity(0.6)
                    VStack(spacing: 8) {
                        Text("Nothing on the board yet")
                            .fontStyle(.headline)
                            .multilineTextAlignment(.center)
                        Text("Be the first to post.")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
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
        // Separated from the board above by more than the masonry's own
        // 16pt row rhythm — this block is a different kind of thing, not
        // another card, so it needs its own air to read as commentary on
        // the board rather than the next item in it.
        .padding(.top, 72)
        .padding(.bottom, 48)
        .padding(.horizontal, 24)
    }
}
