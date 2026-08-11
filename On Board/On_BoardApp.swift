//
//  On_BoardApp.swift
//  On Board
//

import GoogleMobileAds
import GoogleSignIn
import Supabase
import SwiftUI
import TipKit

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

    @MainActor
    static func makeEntitlementStore() -> EntitlementStore {
        // Mock-backed for now (StoreKit needs a StoreKit config, not Supabase);
        // the factory swaps in the real service later without touching callers.
        EntitlementStore(service: SubscriptionServiceFactory.make())
    }

    @MainActor
    static func makeAdsGateway(entitlement: EntitlementStore) -> AdsGateway {
        AdsGateway(entitlement: entitlement)
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
    @State private var entitlement: EntitlementStore
    @State private var ads: AdsGateway
    @State private var remoteConfig = RemoteConfigStore()

    init() {
        NavigationBarAppearance.configureIfNeeded()
        OnBoardImagePipeline.configure()
        let authStore = AppLaunchContext.makeAuthStore()
        let networkMonitor = NetworkMonitor()
        let entitlementStore = AppLaunchContext.makeEntitlementStore()
        _auth = State(wrappedValue: authStore)
        _network = State(wrappedValue: networkMonitor)
        _onboarding = State(wrappedValue: AppLaunchContext.makeOnboardingStore(
            auth: authStore,
            network: networkMonitor
        ))
        _entitlement = State(wrappedValue: entitlementStore)
        // Must share the SAME EntitlementStore instance as `entitlement` above —
        // a second, disconnected instance would let AdsGateway check a store
        // that never learns about a real purchase/restore.
        _ads = State(wrappedValue: AppLaunchContext.makeAdsGateway(entitlement: entitlementStore))
        // Local-only (no CloudKit sync), no artificial throttling beyond each
        // Tip's own rules — one donation per cold launch, used by ArchiveTip's
        // "shown after the 2nd launch" rule.
        // `-dev.disableTips`: keeps TipKit popovers out of headless
        // walkthrough screenshots — every fresh sim install resets the tip
        // datastore, so the Archive tip otherwise photobombs every capture.
        if ProcessInfo.processInfo.arguments.contains("-dev.disableTips") {
            Tips.hideAllTipsForTesting()
        } else {
            try? Tips.configure([.datastoreLocation(.applicationDefault), .displayFrequency(.immediate)])
        }
        Task { await ArchiveTip.appLaunchEvent.donate() }

        // SDK init only — this does NOT load or show any ad. Whether an ad is
        // ever actually requested is decided later, per-call, by AdsGateway
        // (which refuses to serve anything once EntitlementStore.isFirstClass
        // is true). Skipped in Xcode canvas previews, matching the other
        // services' `isPreview` guard.
        if !AppLaunchContext.isPreview {
            MobileAds.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color(UIColor(named: "AccentColor") ?? .label))
                .environment(store)
                .environment(auth)
                .environment(onboarding)
                .environment(network)
                .environment(entitlement)
                .environment(ads)
                // BoardStore composes the feed and therefore decides where promoted
                // slots go, but it must never read entitlements itself. Mirror the
                // gate's answer in as a plain Bool, and keep it mirrored — the feed
                // should drop its ad slots the instant someone subscribes, not on
                // the next refresh.
                .onChange(of: ads.isEligibleForAds, initial: true) { _, eligible in
                    store.adsEligible = eligible
                }
                .environment(remoteConfig)
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

                    // Deep-link profile sharing
                    // Universal Link: https://onboardapp.org/profile/<UUID>
                    // Custom Scheme: onboard://profile/<UUID>
                    let isProfileUniversalLink = url.host == "onboardapp.org" && url.pathComponents.count >= 3 && url.pathComponents[1] == "profile"
                    let isProfileCustomScheme = url.scheme == "onboard" && url.host == "profile" && url.pathComponents.count >= 2

                    if isProfileUniversalLink || isProfileCustomScheme {
                        if let uuidString = url.pathComponents.last, let profileID = UUID(uuidString: uuidString) {
                            NotificationService.shared.setPendingProfileID(profileID)
                            return
                        }
                    }

                    // Deep-link referral code
                    // Universal Link: https://onboardapp.org/invite/XXX (canonical —
                    // matches the web landing route) or /invite?code=XXX
                    // Custom Scheme: onboard://invite/XXX or onboard://invite?code=XXX
                    let isInviteUniversalLink = url.host == "onboardapp.org" && url.pathComponents.count >= 2 && url.pathComponents[1] == "invite"
                    let isInviteCustomScheme = url.scheme == "onboard" && url.host == "invite"

                    if isInviteUniversalLink || isInviteCustomScheme {
                        let queryCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value
                        let pathCode: String? = {
                            if isInviteUniversalLink, url.pathComponents.count >= 3 { return url.pathComponents[2] }
                            if isInviteCustomScheme, url.pathComponents.count >= 2 { return url.pathComponents[1] }
                            return nil
                        }()
                        if let code = (queryCode ?? pathCode)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !code.isEmpty {
                            PendingReferralCode.store(code)
                        }
                        return
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
                        } else if event == .signedOut {
                            // Ignored when the app initiated the sign-out; only
                            // fires for externally-revoked sessions.
                            await auth.handleExternalSignOut()
                        }
                    }
                }
        }
    }
}
