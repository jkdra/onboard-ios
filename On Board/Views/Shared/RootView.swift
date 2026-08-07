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
    @Environment(RemoteConfigStore.self) private var remoteConfig
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    @State private var didBootstrap = false
    /// Flips the launch mark from the idle Host to the happy one just before the
    /// hand-off to the app. Separate from `didBootstrap` because the smile has to land
    /// while the launch view is still on screen.
    @State private var bootstrapHostHappy = false

    /// How long the smile holds before the fade. `-dev.bootstrapHold <secs>`
    /// stretches it for inspection — the shipped beat is far too short to catch with a
    /// screenshot loop, and a simulator recording only samples on screen *change*.
    private static let bootstrapHoldSeconds: Double = {
        let override = UserDefaults.standard.double(forKey: "dev.bootstrapHold")
        return override > 0 ? override : 0.20
    }()

    /// Welcome celebration: set while this session has shown an incomplete
    /// onboarding status, so the flip to complete is a real live admission
    /// (waitlist approval or golden-ticket verify) — never a returning user
    /// whose status simply loads as complete.
    @State private var sawIncompleteOnboarding = false
    @State private var showWelcome = false

    private var requiresNetwork: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    private var shouldShowOfflineGate: Bool {
        guard requiresNetwork else { return false }
        if auth.state == .restoreFailedOffline { return true }
        return network.hasReceivedUpdate && !network.isConnected
    }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if remoteConfig.config.updateRequirement() == .required {
                // A root branch, not a presentation — same mechanism as the
                // offline gate below, and for the same reason: this must never
                // silently fail to appear. Checked first: an out-of-date build
                // is out of date regardless of connectivity or bootstrap state.
                UpdateRequiredWall()
            } else if shouldShowOfflineGate {
                OfflineGateView {
                    network.recheck()
                    Task { await retryAfterConnectivityRestored() }
                }
            } else if !didBootstrap {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    // Hard swap, no cross-fade: the two sprites share a canvas, so
                    // the expression changes without the mark shifting or ghosting.
                    Image(bootstrapHostHappy ? "HostHappy" : "HostIdle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        // Host sprites are solid black art and don't tint, so they'd
                        // disappear into a dark launch background without this.
                        .colorInverted(scheme == .dark)
                }
            } else {
                mainContent
            }
        }
        // Config-driven environment values are injected HERE, on the root
        // Group, so every branch sees them — ContentView and
        // OnboardingCoordinator are siblings, and injecting these on
        // ContentView (as originally shipped) left the onboarding subtree
        // reading each EnvironmentKey's compiled default: the profile step
        // validated against hardcoded limits and the progress bar ignored the
        // glass kill switch. Set once here rather than read per leaf view:
        // RemoteConfigStore is not in a #Preview's environment, and
        // @Environment(_:.self) traps when the object is absent.
        .environment(\.glassEffectsEnabled, remoteConfig.isEnabled(.glassEffects, for: auth.session?.userId))
        .environment(\.photoAttachmentsEnabled, remoteConfig.isEnabled(.postPhotoAttachments, for: auth.session?.userId))
        // Falls back to the compiled set when unset, so the bar is never empty.
        .environment(\.enabledReactions, remoteConfig.config.enabledReactions ?? Reaction.defaultOrder)
        .environment(\.reactionOverflowEnabled, remoteConfig.isEnabled(.reactionOverflow, for: auth.session?.userId))
        .environment(\.commentMaxLength, remoteConfig.config.commentMaxLength)
        .environment(\.profileFieldLimits, (displayName: remoteConfig.config.displayNameMaxLength,
                                            bio: remoteConfig.config.bioMaxLength))
        .environment(\.handleChangeRule, (windowDays: remoteConfig.config.handleChangeWindowDays,
                                          maxPerWindow: remoteConfig.config.handleChangeMaxPerWindow))
        .animation(.smooth, value: auth.isSignedIn)
        .animation(.smooth, value: onboarding.isComplete)
        .task {
            network.start()
            // Deliberately not awaited: config must never sit on the launch
            // path. A failed or slow fetch leaves the last-known (or compiled
            // default) values in place, which is always a usable app.
            Task { await remoteConfig.refresh() }
            store.configure(configuration: AppConfiguration.current)
            // From the *cached* config, synchronously — the fetch above hasn't
            // landed yet. The .onChange(of: remoteConfig.config) below re-runs
            // this the moment any fetch actually changes something, so the
            // imperative consumers are never a refresh cycle behind the
            // observable ones.
            applyImperativeConfig()
            await auth.restoreSession()
            await syncSessionState()
            // Smile, hold briefly, then hand off. This deliberately adds ~0.33s to
            // launch — the beat only exists to be seen, so it can't overlap the work
            // it's celebrating. Skipped entirely under Reduce Motion, where it would
            // be a pause with nothing to show for it.
            if !reduceMotion {
                // Hard cut. `auth.isSignedIn` / `onboarding.isComplete` both settle
                // during bootstrap and carry `.smooth` animations on the Group below,
                // and that ambient transaction was cross-fading the sprite swap — the
                // two expressions blended into a smeared eye. Only the hand-off into
                // the app should be smooth.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { bootstrapHostHappy = true }
                try? await Task.sleep(for: .seconds(Self.bootstrapHoldSeconds))
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                didBootstrap = true
            }
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
            // Above the isSignedIn guard on purpose — the version gate and any
            // auth-flow flag have to stay fresh for signed-out users too. The
            // config onChange below picks up whatever this fetch changes.
            Task { await remoteConfig.refresh() }
            guard auth.isSignedIn else { return }
            Task { await onboarding.refreshOnForeground() }
        }
        // The imperative consumers (HostVoice, BoardStore's copies) don't
        // observe RemoteConfigStore, so re-apply them whenever a fetch lands a
        // real change. Without this they ran one full refresh cycle stale: a
        // flag pulled mid-incident took effect on the SECOND foreground, not
        // the first.
        .onChange(of: remoteConfig.config) { _, _ in
            applyImperativeConfig()
        }
        .onChange(of: onboarding.needsOnboarding) { _, needsOnboarding in
            if needsOnboarding {
                sawIncompleteOnboarding = true
                // Persist it per-user so a cold launch after an away-admission
                // (admin admit → "You're On Board!" push, app killed in between)
                // still fires the welcome — the in-session flag alone would miss it.
                if let userID = auth.session?.userId {
                    WelcomeCelebration.markSeenIncomplete(for: userID)
                }
            }
        }
        .onChange(of: onboarding.isComplete) { _, isComplete in
            guard isComplete,
                  let userID = auth.session?.userId,
                  sawIncompleteOnboarding || WelcomeCelebration.wasSeenIncomplete(for: userID),
                  !WelcomeCelebration.hasShown(for: userID) else { return }
            WelcomeCelebration.markShown(for: userID)
            showWelcome = true
        }
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            if !isSignedIn { sawIncompleteOnboarding = false }
            // hostVoice buckets per user, so its resolution can flip on
            // sign-in/out even though the config itself didn't change.
            applyImperativeConfig()
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeOnBoardView(boardName: onboarding.status?.boardName)
                .preferredColorScheme(appearance.colorScheme)
        }
    }



    @ViewBuilder
    private var mainContent: some View {
        if auth.isSignedIn, case .failed(let message) = onboarding.loadState {
            onboardingErrorView(message)
        } else if auth.isSignedIn, onboarding.isComplete {
            ContentView()
                // Soft update prompt: on the settled post-bootstrap tree
                // (presenting from the outer Group during the bootstrap swap is
                // how it silently failed to appear), and deliberately on the
                // FEED branch only — as a bottom overlay it composited over the
                // sign-in/onboarding funnel, covering low-anchored Continue
                // buttons with a dismissible nag. A user mid-funnel gets it
                // right here the moment they land. No-op until
                // recommended_version is seeded.
                .updatePrompt(remoteConfig.config.updateRequirement(),
                              offeredVersion: remoteConfig.config.recommendedVersion)
                .preferredColorScheme(appearance.colorScheme)
        } else {
            // Covers: not signed in, signed in + loading status, signed in + needs onboarding.
            // The coordinator owns SignInView at its root and handles all transitions internally.
            OnboardingCoordinator()
        }
    }



    /// Pushes config into the consumers that can't observe RemoteConfigStore
    /// themselves: HostVoice is an imperative engine (a static isn't
    /// observable), and BoardStore holds copies because a model object can't
    /// read the SwiftUI environment. Called from the launch task (cached
    /// config, synchronously), from the config onChange (fresh fetches), and
    /// on sign-in/out (per-user flag bucketing).
    private func applyImperativeConfig() {
        HostVoice.isEnabled = remoteConfig.isEnabled(.hostVoice, for: auth.session?.userId)
        store.archiveWeekCacheLimit = remoteConfig.config.maxCachedArchiveWeeks
        store.boardThresholds = remoteConfig.config.boardThresholds
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
        if auth.state == .restoreFailedOffline {
            await auth.restoreSession()
            await syncSessionState()
            return
        }
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

            if let status = onboarding.status {
                let profile = Profile(
                    id: status.id,
                    handle: status.handle,
                    displayName: status.displayName,
                    bio: status.bio,
                    avatarUrl: status.avatarUrl
                )
                store.upsertProfile(profile)
            }

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
        .environment(RemoteConfigStore())
}
