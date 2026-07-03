//
//  RootView.swift
//  On Board
//
//  App shell: sign-in gate, onboarding, then the board feed.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(BoardStore.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.scenePhase) private var scenePhase

    @State private var didBootstrap = false

    #if DEBUG
    @State private var devForceOnboarding = false
    #endif

    private var requiresNetwork: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    private var shouldShowOfflineGate: Bool {
        requiresNetwork && network.hasReceivedUpdate && !network.isConnected
    }

    var body: some View {
        Group {
            if shouldShowOfflineGate {
                OfflineGateView {
                    network.recheck()
                    Task { await retryAfterConnectivityRestored() }
                }
            } else {
                mainContent
            }
        }
        .task {
            network.start()
            store.configure(configuration: AppConfiguration.current)
            await auth.restoreSession()
            await syncSessionState()
            didBootstrap = true
        }
        .onChange(of: sessionSyncToken) { _, _ in
            guard didBootstrap else { return }
            Task { await syncSessionState() }
        }
        .onChange(of: network.isConnected) { _, isConnected in
            guard didBootstrap, isConnected else { return }
            Task { await retryAfterConnectivityRestored() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard didBootstrap, phase == .active else { return }
            network.recheck()
            guard auth.isSignedIn else { return }
            Task { await onboarding.refreshIfOnline() }
        }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) { developerOverrideButton }
        #endif
    }

    #if DEBUG
    private var developerOverrideButton: some View {
        Button {
            withAnimation(.smooth) { devForceOnboarding.toggle() }
        } label: {
            Label(devForceOnboarding ? "Exit Override" : "Developer Override",
                  systemImage: devForceOnboarding ? "xmark" : "hammer.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .tint(.primary)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .opacity(0.85)
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        if debugForceOnboarding {
            // DEBUG: walk the real onboarding screens with on-screen Next/Back.
            OnboardingCoordinator(devDriven: true)
        } else if auth.isSignedIn, case .failed(let message) = onboarding.loadState {
            onboardingErrorView(message)
        } else if auth.isSignedIn, onboarding.isComplete {
            BoardListView()
        } else {
            // Covers: not signed in, signed in + loading status, signed in + needs onboarding.
            // The coordinator owns SignInView at its root and handles all transitions internally.
            OnboardingCoordinator()
        }
    }

    private var debugForceOnboarding: Bool {
        #if DEBUG
        devForceOnboarding
        #else
        false
        #endif
    }

    /// One orchestration path per auth/onboarding change — avoids duplicate refresh RPCs.
    private var sessionSyncToken: SessionSyncToken {
        SessionSyncToken(auth: auth.state, onboardingComplete: onboarding.isComplete)
    }

    private func syncSessionState() async {
        if auth.isSignedIn {
            await onboarding.refreshIfOnline()
            if onboarding.isComplete {
                await syncBoardState()
            }
        } else {
            onboarding.reset()
            await syncBoardState()
        }
    }

    private func retryAfterConnectivityRestored() async {
        guard network.isConnected else { return }
        if auth.isSignedIn {
            await onboarding.refresh()
            if onboarding.isComplete {
                await syncBoardState()
                store.restartReactionRealtime()
            }
        }
    }

    private func syncBoardState() async {
        let configuration = AppConfiguration.current

        if let session = auth.session, onboarding.isComplete {
            store.setCurrentUser(id: session.userId)

            if let boardId = onboarding.status?.boardId {
                store.setBoard(id: boardId, name: onboarding.status?.boardName)
            }

            // Only refresh when the user has been assigned a board. Without this guard,
            // waitlisted users (boardId == nil) would trigger a refresh that falls back
            // to SampleBoardID.main and loads demo data into the holding screen.
            if configuration.isSupabaseConfigured, network.isConnected, store.currentBoardId != nil {
                await store.refresh(for: session.userId)
            }
        } else {
            store.clearCurrentUser()
            store.resetForSignOut()
        }
    }

    private func onboardingErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load onboarding")
                .fontStyle(.headline)
            Text(message)
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await onboarding.refresh() }
            }
            .buttonStyle(.boardPrimary)

            Button("Sign out") {
                Task { await auth.signOut() }
            }
            .fontStyle(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionSyncToken: Equatable {
    let auth: AuthState
    let onboardingComplete: Bool
}

#Preview {
    RootView()
        .environment(AuthStore(service: MockAuthService()))
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
        .environment(BoardStore.previewBoard())
        .environment(NetworkMonitor())
}
