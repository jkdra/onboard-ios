//
//  ContentView.swift
//  On Board
//
//  Home feed for the active board week.
//

import SwiftUI

struct ContentView: View {

    @Environment(BoardStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @State private var navigationPath: [BoardRoute] = []
    @State private var showNewPost = false
    @State private var boardIsResetting = false
    @State private var pulseLowOpacity = false
    @State private var alertError: PresentableAlertError?
    @State private var isResolvingPendingProfile = false
    @State private var showWelcomeReplay = false
    @Namespace private var cardNamespace

    private var clearingSoon: Bool {
        BoardSchedule.isClearingSoon(weekEnd: store.activeBoardWeek?.endsAt)
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
        .environment(\.cardNamespace, cardNamespace)
        // Notification deep-link: fires on warm relaunch (post already cached),
        // on a tap while the app is alive, and after the cold-launch fetch
        // settles (isLoading flips false) — whichever happens first.
        .onAppear { openPendingPostIfReady() }
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
                if onboarding.supportsDevAdmission {
                    Button("Replay Welcome [DEV]") {
                        showWelcomeReplay = true
                    }
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }

                BoardFeedView(
                    items: feedItems,
                    onNewPost: { showNewPost = true },
                    isResetting: boardIsResetting
                )

                if store.isLive, !store.isLoading, !store.hasFeedPosts {
                    emptyFeedState
                }
            }

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
        .task {
            // No realtime subscription for reactions/posts (removed — the app is
            // weekly-cadence, not a live chat, so instant cross-user updates aren't
            // worth the always-on connection). This silent poll is the replacement:
            // pull-to-refresh and foreground-refresh cover the rest.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                await store.refresh(for: store.currentUserID)
            }
        }
        .task(id: store.activeBoardWeek?.endsAt) {
            guard let endsAt = store.activeBoardWeek?.endsAt, endsAt > .now else { return }
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await triggerBoardReset()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        navigationPath.append(BoardRoute.archive)
                    } label: {
                        Label("Archive", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    Button {
                        navigationPath.append(BoardRoute.settings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis").fontWeight(.semibold)
                }
                .accessibilityLabel("More")
            }
        }
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
                    .navigationTransition(.zoom(sourceID: route, in: cardNamespace))
            }
        case .postFromProfile(let postID, let profileID):
            if let post = store.post(with: postID) {
                PostDetailView(post: post)
                    .environment(store)
                    .environment(\.originatingProfileID, profileID)
                    .navigationTransition(.zoom(sourceID: route, in: cardNamespace))
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

    private func triggerBoardReset() async {
        showNewPost = false
        if !navigationPath.isEmpty { navigationPath.removeAll() }
        try? await Task.sleep(for: .milliseconds(400))
        boardIsResetting = true
        let postCount = store.feedItems.filter { if case .post = $0 { return true }; return false }.count
        let animDuration = Double(max(postCount, 1)) * 0.07 + 0.7
        try? await Task.sleep(for: .seconds(animDuration))
        await store.refresh(for: store.currentUserID)
        boardIsResetting = false
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
}

#Preview("Live Feed") {
    LiveFeedPreview()
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
