//
//  On_BoardApp.swift
//  On Board
//

import GoogleSignIn
import SwiftUI

let fontName: String = "ZalandoSansExpanded-Regular"

private enum AppLaunchContext {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static var boardStore: BoardStore {
        (isPreview || !AppConfiguration.current.isSupabaseConfigured)
            ? BoardStore.previewBoard()
            : BoardStore()
    }

    @MainActor
    static func makeAuthStore() -> AuthStore {
        AuthStore(service: isPreview ? MockAuthService() : AuthServiceFactory.make())
    }

    @MainActor
    static func makeOnboardingStore(auth: AuthStore, network: NetworkMonitor) -> OnboardingStore {
        OnboardingStore(
            service: isPreview ? MockOnboardingService() : OnboardingServiceFactory.make(),
            auth: auth,
            network: network
        )
    }
}

@main
struct On_BoardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = AppLaunchContext.boardStore
    @State private var network = NetworkMonitor()
    @State private var auth = AppLaunchContext.makeAuthStore()
    @State private var onboarding: OnboardingStore

    init() {
        NavigationBarAppearance.configureIfNeeded()
        let authStore = AppLaunchContext.makeAuthStore()
        let networkMonitor = NetworkMonitor()
        _auth = State(wrappedValue: authStore)
        _network = State(wrappedValue: networkMonitor)
        _onboarding = State(wrappedValue: AppLaunchContext.makeOnboardingStore(
            auth: authStore,
            network: networkMonitor
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .environment(onboarding)
                .environment(network)
                .onOpenURL { url in
                    // Let GoogleSignIn handle its own callback URL first.
                    if GoogleSignInService.handle(url) { return }
                    // Supabase OAuth deep-link callback.
                    guard url.scheme == AppConfiguration.authRedirectURL.scheme else { return }
                    _ = url
                }
                .onChange(of: auth.session) { _, session in
                    if let userID = session?.userId {
                        Task { await NotificationService.shared.onSignedIn(userID: userID) }
                    } else {
                        NotificationService.shared.onSignedOut()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, let userID = auth.session?.userId else { return }
                    Task { await NotificationService.shared.updateLastSeen(userID: userID) }
                }
        }
    }
}
