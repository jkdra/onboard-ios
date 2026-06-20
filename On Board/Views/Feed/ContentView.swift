//
//  ContentView.swift
//  On Board
//
//  Home feed for the active board week.
//

import SwiftUI
import Combine

struct ContentView: View {

    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @State private var showSettings = false
    @State private var path: [BoardRoute] = []
    @State private var showNewPost = false
    @State private var clearingSoon = false
    @State private var pulseLowOpacity = false
    @Namespace private var cardNamespace

    var body: some View {
        NavigationStack(path: $path) {
            thisWeekFeed
                .navigationDestination(for: BoardRoute.self, destination: routeDestination)
        }
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewPost) { NewPostView() }
    }

    private var thisWeekFeed: some View {
        ScrollView {
            BoardFeedView(
                items: store.feedItems,
                cardNamespace: cardNamespace,
                onNewPost: { showNewPost = true }
            )
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
        .onAppear { updateClearingSoon() }
        .onChange(of: store.activeBoardWeek?.endsAt) { _, _ in
            updateClearingSoon()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            updateClearingSoon()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    Button {
                        path.append(.archive)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
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
        case .post(let postID):
            if let post = store.post(with: postID) {
                PostDetailView(post: post)
                    .navigationTransition(.zoom(sourceID: postID, in: cardNamespace))
            }
        case .profile(let profile):
            ProfileView(profile: profile, presentation: .navigation)
        }
    }

    private func updateClearingSoon() {
        clearingSoon = BoardSchedule.isClearingSoon(weekEnd: store.activeBoardWeek?.endsAt)
    }
}

#Preview("This Week") {
    ContentView()
        .environment(BoardStore.previewBoard())
        .environment(AuthStore(service: MockAuthService()))
}

#Preview("Archive Flow") {
    ContentView()
        .environment(BoardStore.previewBoard())
        .environment(AuthStore(service: MockAuthService()))
}
