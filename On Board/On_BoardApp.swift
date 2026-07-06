//
//  On_BoardApp.swift
//  On Board
//

import GoogleSignIn
import Supabase
import SwiftUI

private enum AppLaunchContext {
    static var isPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        // XCODE_RUNNING_FOR_PREVIEWS = legacy/static previews
        // XCODE_RUNNING_FOR_PLAYGROUNDS = JIT previews (iOS 16+, Xcode 15+)
        return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
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
    @State private var network: NetworkMonitor
    @State private var auth: AuthStore
    @State private var onboarding: OnboardingStore

    init() {
        NavigationBarAppearance.configureIfNeeded()
        OnBoardImagePipeline.configure()
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
                .tint(Color(UIColor(named: "AccentColor") ?? .label))
                .environment(store)
                .environment(auth)
                .environment(onboarding)
                .environment(network)
                .onOpenURL { url in
                    // Let GoogleSignIn handle its own callback URL first.
                    if GoogleSignInService.handle(url) { return }
                    
                    // Deep-link post sharing
                    // Universal Link: https://onboardapp.org/post/<UUID>
                    // Custom Scheme: onboard://post/<UUID>
                    let isUniversalLink = url.host == "onboardapp.org" && url.pathComponents.count >= 3 && url.pathComponents[1] == "post"
                    let isCustomScheme = url.scheme == "onboard" && url.host == "post" && url.pathComponents.count >= 2
                    
                    if isUniversalLink || isCustomScheme {
                        if let uuidString = url.pathComponents.last, let postID = UUID(uuidString: uuidString) {
                            NotificationService.shared.setPendingPostID(postID)
                            return
                        }
                    }

                    // Deep-link OAuth callbacks (linkIdentity's default URL opener, web
                    // OAuth fallback) resolve via UIApplication.open, not an in-app
                    // ASWebAuthenticationSession — per the SDK's own docs, the app must
                    // forward the callback URL to `auth.handle(_:)` or the flow never
                    // completes (was previously a silent no-op here).
                    SupabaseClientFactory.client(for: .current)?.auth.handle(url)
                }
                .onChange(of: auth.session) { _, session in
                    if let userID = session?.userId {
                        Task { await NotificationService.shared.onSignedIn(userID: userID) }
                    } else {
                        NotificationService.shared.onSignedOut()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    NotificationService.shared.clearBadge()
                    guard let userID = auth.session?.userId else { return }
                    Task { await NotificationService.shared.updateLastSeen(userID: userID) }
                }
                .task {
                    // Magic links and external deep-links process via client.auth.handle(url)
                    // silently in the background. We must observe the SDK's auth state
                    // changes to sync the UI when those external sign-ins succeed.
                    guard let client = SupabaseClientFactory.client(for: .current) else { return }
                    for await (event, _) in client.auth.authStateChanges {
                        if event == .signedIn && !auth.isSignedIn {
                            await auth.restoreSession()
                        }
                    }
                }
        }
    }
}
