//
//  ContentView.swift
//  On Board
//
//  Home feed for the active board week.
//
//  Split across files: `ContentView+Views.swift` (thisWeekFeed, route
//  destinations, empty state) and `ContentView+Logic.swift` (pending
//  deep-link routes, weekly reset choreography). The @Namespace and all
//  @State stay here; state and helpers those extensions read are `internal`
//  rather than `private` solely because extensions in other files can't
//  reach private members.
//

import SwiftUI
import TipKit

struct ContentView: View {

    @Environment(BoardStore.self) var store
    @Environment(AuthStore.self) private var auth
    @Environment(OnboardingStore.self) var onboarding
    @Environment(RemoteConfigStore.self) var remoteConfig
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("appearance") var appearance: AppearancePreference = .system

    @State var navigationPath: [BoardRoute] = []
    @State var archiveTip = ArchiveTip()
    @State var showNewPost = false
    @State var boardIsResetting = false
    @State var pulseLowOpacity = false
    @State var alertError: PresentableAlertError?
    @State var isResolvingPendingProfile = false
    @State var showWelcomeReplay = false
    /// Fires the once-a-year birthday celebration (fireworks + the countdown
    /// card's greeting) when the current user's birthday is today.
    @State var birthdayCelebrating = false
    /// True while the in-feed new-post card is at least partly on screen. When it
    /// scrolls away (and posting is still open), the bottom-bar compose button appears.
    @State var newPostCardVisible = true
    /// Drives the programmatic snap-to-top at the start of the weekly reset.
    @State var feedScrollPosition = ScrollPosition()
    /// Announces the turnover. Without it the board's entire contents changed with no
    /// acknowledgement — a post you were reading would just evaporate.
    @State var showBoardClearedToast = false
    /// True while the take-down has finished but the server hasn't produced the new
    /// week yet (device clock ahead of the server's rollover). The board is already
    /// swept, so this drives the "Setting up this week's board…" indicator.
    @State var settingUpNewBoard = false
    /// Last week id this view has seen, so a week arriving on its own (poll, foreground
    /// refresh) can be told apart from the one we rolled over ourselves.
    @State var lastKnownWeekID: UUID?
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
    var activeCardNamespace: Namespace.ID? {
        remoteConfig.isEnabled(.zoomTransition, for: auth.session?.userId) ? cardNamespace : nil
    }

    /// DEV/mock-only: the in-feed dev scratch block (Signal Lost preview, tint/aspect
    /// pickers) fills roughly 1.5 screens above the masonry, so a snap-to-top during a
    /// UI-test walkthrough frames the controls instead of the feed. Pass
    /// `-dev.hideDevBlock` to suppress it and see the real board.
    static let hidesDevBlock =
        ProcessInfo.processInfo.arguments.contains("-dev.hideDevBlock")

    /// DEV/mock-only: `-dev.openPostIndex <n>` pushes the nth feed post's
    /// detail on appear. Exists because synthesized taps are broken under the
    /// current Xcode's XCUITest (see ReactionBarInsetUITests) and headless
    /// walkthroughs still need to reach PostDetailView.
    private static let devOpenPostIndex: Int? =
        ProcessInfo.processInfo.arguments.contains("-dev.openPostIndex")
            ? UserDefaults.standard.integer(forKey: "dev.openPostIndex") : nil

    var clearingSoon: Bool {
        BoardSchedule.isClearingSoon(weekEnd: store.activeBoardWeek?.endsAt,
                                     thresholds: remoteConfig.config.boardThresholds)
    }

    /// True only while the feed actually contains an *enabled* compose card — i.e.
    /// an interactive week outside the final hour. Gates the bottom-bar button so it
    /// never appears on archived weeks or once posting has closed.
    var postingEnabled: Bool {
        store.feedItems.contains {
            if case .newPost(let isEnabled, _) = $0 { return isEnabled }
            return false
        }
    }

    /// Shows the bottom-bar compose button once the in-feed card is scrolled away.
    var showsBottomBarNewPost: Bool {
        postingEnabled && !newPostCardVisible
    }

    /// iOS 26 gives `.bottomBar` a liquid-glass background the button rides on; on
    /// earlier versions we hide that background and let the button wear its own material.
    var isIOS26OrLater: Bool {
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
        .onAppear {
            // DEV: `-dev.emptyBoard` rolls the seeded mock week over into a
            // fresh empty one — the only headless way to reach the
            // fresh-Monday empty state (the Host's empty-board canvas).
            // Mock-only by devRollOverWeek's own isLive guard.
            guard ProcessInfo.processInfo.arguments.contains("-dev.emptyBoard") else { return }
            _ = store.devRollOverWeek()
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
