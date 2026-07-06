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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var navigationPath = NavigationPath()
    @State private var showNewPost = false
    @State private var timerTick = 0
    @State private var boardIsResetting = false
    @State private var pulseLowOpacity = false
    @State private var alertError: PresentableAlertError?
    @Namespace private var cardNamespace

    private var clearingSoon: Bool {
        BoardSchedule.isClearingSoon(weekEnd: store.activeBoardWeek?.endsAt)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            thisWeekFeed
                .navigationDestination(for: BoardRoute.self, destination: routeDestination)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                navigationPath = NavigationPath()
                                dismiss()
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .accessibilityLabel("Boards")
                        }
                    }
                }
                .sheet(isPresented: $showNewPost) { NewPostView() }
                .boardErrorHandling(alertError: $alertError, suppressWhenBoardMissing: true)
                .presentableErrorAlert(error: $alertError)
        }
        // Notification deep-link: fires on warm relaunch (post already cached),
        // on a tap while the app is alive, and after the cold-launch fetch
        // settles (isLoading flips false) — whichever happens first.
        .onAppear { openPendingPostIfReady() }
        .onChange(of: NotificationService.shared.pendingPostID) { _, _ in
            openPendingPostIfReady()
        }
        .onChange(of: store.isLoading) { _, loading in
            if !loading { openPendingPostIfReady() }
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
            navigationPath = NavigationPath([BoardRoute.post(postID)])
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

    private var thisWeekFeed: some View {
        let feedItems = store.feedItems
        return ZStack {
            ScrollView {
                BoardFeedView(
                    items: feedItems,
                    cardNamespace: cardNamespace,
                    onNewPost: { showNewPost = true },
                    isResetting: boardIsResetting
                )

                if store.isLive, !store.isLoading, !store.hasFeedPosts {
                    emptyFeedState
                }
            }

            if store.isLoading, store.posts.isEmpty {
                ProgressView("Loading your board…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        .navigationTitle("This Week")
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                timerTick &+= 1
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
                Button {
                    navigationPath.append(BoardRoute.archive)
                } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .accessibilityLabel("Archive")
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
        case .post(let postID):
            if let post = store.post(with: postID) {
                PostDetailView(post: post)
                    .environment(store)
                    .navigationTransition(.zoom(sourceID: postID, in: cardNamespace))
            }
        case .profile(let profile):
            ProfileView(profile: profile, presentation: .navigation)
        }
    }

    private func triggerBoardReset() async {
        showNewPost = false
        if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
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
                            .font(.caption)
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
