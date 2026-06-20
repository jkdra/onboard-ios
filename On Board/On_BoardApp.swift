//
//  On_BoardApp.swift
//  On Board
//

import SwiftUI

let fontName: String = "ZalandoSansExpanded-Regular"

private enum AppLaunchContext {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static var boardStore: BoardStore {
        isPreview ? BoardStore.previewBoard() : BoardStore()
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
        }
    }
}
