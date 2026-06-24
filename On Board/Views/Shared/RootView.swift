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
    }

    @ViewBuilder
    private var mainContent: some View {
        if auth.isSignedIn, case .failed(let message) = onboarding.loadState {
            onboardingErrorView(message)
        } else if auth.isSignedIn, onboarding.isComplete {
            BoardListView()
        } else {
            // Covers: not signed in, signed in + loading status, signed in + needs onboarding.
            // The coordinator owns SignInView at its root and handles all transitions internally.
            OnboardingCoordinator()
        }
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

            if configuration.isSupabaseConfigured {
                if network.isConnected {
                    await store.refresh(for: session.userId)
                }
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
