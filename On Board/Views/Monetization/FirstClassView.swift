//
//  FirstClassView.swift
//  On Board
//
//  The On Board First Class screen — pushed from the boarding-pass card in
//  Settings. Fully custom (not StoreKit's SubscriptionStoreView) so the ticket
//  design keeps full control. Drives against `EntitlementStore`; in this slice
//  that's mock-backed, so purchase/restore flip a local flag. `isFirstClass`
//  swaps the whole screen between the sell and the membership pass.
//

import SwiftUI

struct FirstClassView: View {
    @Environment(EntitlementStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("soundEffectsMode") private var soundMode: SoundEffectsMode = .unlessSilenced
    @State private var selectedPlan: FirstClassPlan = .yearly
    @State private var perksAppeared = false
    @State private var showCelebration = false
    @State private var celebrationLine = ""
    @State private var celebrationTask: Task<Void, Never>?
    private let topAnchor = "firstClassTop"
    private let fullCelebrationLine = "Welcome aboard, First Class!"

    private var selectedProduct: FirstClassProduct? {
        store.products.first { $0.plan == selectedPlan } ?? store.products.first
    }

    var body: some View {
        @Bindable var store = store

        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 26) {
                    Color.clear.frame(height: 0).id(topAnchor)

                    FirstClassBoardingPassCard(
                        mode: store.isFirstClass ? .member(renewal: renewalNote) : .promo,
                        isHero: true
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .fireworks(isActive: showCelebration)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    if store.isFirstClass {
                        memberBody
                    } else {
                        promoBody
                    }

                    devRevertButton
                }
                .padding(.bottom, 40)
                .animation(.snappy(duration: 0.35), value: store.isFirstClass)
            }
            // The promo layout's CTA sits well below the fold; a purchase swaps
            // in the shorter member layout while keeping the scroll view's old
            // offset, which stranded the celebration title and hero card above
            // the visible area (mid-perks was the first thing a buyer saw).
            // Scroll back to top whenever the screen becomes First Class.
            .onChange(of: store.isFirstClass) { wasFirstClass, isFirstClass in
                guard isFirstClass else { return }
                withAnimation(.snappy(duration: 0.35)) {
                    scrollProxy.scrollTo(topAnchor, anchor: .top)
                }
                // Only celebrate a fresh purchase/restore transition, not a
                // screen that was already subscribed when it appeared.
                guard !wasFirstClass else { return }
                startCelebration()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
        .presentableErrorAlert(error: $store.alertError)
        .onDisappear { celebrationTask?.cancel() }
    }

    // MARK: - Dev

    /// Temporary: drops the simulated membership so the promo → purchase →
    /// celebration → member run can be walked again without deleting the app.
    ///
    /// `#if DEBUG` rather than a runtime flag on purpose — this must be impossible
    /// to reach in a distributed build, and the compiler is the only guarantee of
    /// that which can't be undone by a stray launch argument. Delete it once real
    /// StoreKit lands, where Xcode's Manage Subscriptions sheet does this properly.
    @ViewBuilder
    private var devRevertButton: some View {
        #if DEBUG
        if store.isFirstClass {
            Button("Revert to No FC [DEV]", role: .destructive) {
                Task { await store.devRevertToFree() }
            }
            .fontStyle(.footnote)
            .padding(.top, 8)
        }
        #endif
    }

    // MARK: - Celebration (fires once, on purchase/restore)

    private var celebrationBubble: some View {
        HStack(alignment: .center, spacing: 4) {
            // Same treatment as the ticket's Host peek: inverted in dark (the
            // app's standard Host dark form), floated with a soft shadow in light.
            Image("HostHappy")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .colorInverted(scheme == .dark)
                .hostFloatShadow(scheme)
                .accessibilityHidden(true)
            HostSpeechBubble {
                Text(celebrationLine)
                    .fontStyle(.subheadline)
                    .fontWeight(.heavy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullCelebrationLine)
    }

    private func startCelebration() {
        celebrationTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            showCelebration = true
        }
        celebrationLine = ""
        celebrationTask = Task {
            if soundMode.isOn { HostVoice.shared.prepare(playsWhenSilenced: true) }
            await typeCelebrationLine()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.3)) { showCelebration = false }
        }
    }

    /// Mirrors `WelcomeOnBoardView`'s character-by-character delivery: the
    /// bubble types on while the Host's Animalese blips play per letter.
    private func typeCelebrationLine() async {
        let chars = Array(fullCelebrationLine)
        for index in 1...chars.count {
            guard !Task.isCancelled else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { celebrationLine = String(chars[0..<index]) }
            if soundMode.isOn {
                HostVoice.shared.speak(chars[index - 1], at: index - 1, in: fullCelebrationLine, bright: true)
            }
            try? await Task.sleep(for: .milliseconds(38))
        }
    }

    // MARK: - Promo (not subscribed)

    private var promoBody: some View {
        VStack(spacing: 28) {
            perksSection

            switch store.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .padding(.vertical, 24)
            case .failed:
                retrySection
            default:
                planPicker
                ctaSection
            }

            legalSection
        }
    }

    private var retrySection: some View {
        VStack(spacing: 12) {
            Text("We couldn't load First Class.")
                .fontStyle(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await store.loadProducts() } }
                .buttonStyle(.boardPrimary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Perks

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ExtraBold (vs the perk titles' Butler Medium) so the section
            // header clearly outranks the smaller titles beneath it.
            Text("What you get")
                .font(ButlerFont.extraBold(22))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            ForEach(Array(FirstClassPerk.advertised.enumerated()), id: \.element.id) { index, perk in
                PerkRow(perk: perk, unlocked: store.isFirstClass, appeared: perksAppeared, revealDelay: Double(index) * 0.05)
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            // Each row animates its own reveal (with its own stagger delay) via
            // `.onChange(of: appeared)` below — this flag just triggers them.
            perksAppeared = true
        }
    }

    // MARK: Plan picker

    private var planPicker: some View {
        HStack(spacing: 12) {
            ForEach(store.products) { product in
                PlanCard(
                    product: product,
                    isSelected: product.plan == selectedPlan
                )
                .onTapGesture {
                    guard selectedPlan != product.plan else { return }
                    if hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedPlan = product.plan
                    }
                }
                .accessibilityAddTraits(product.plan == selectedPlan ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                guard let product = selectedProduct else { return }
                Task { await store.purchase(product) }
            } label: {
                LoadingButtonLabel(
                    ctaTitle,
                    systemImage: "airplane.departure",
                    isLoading: store.state == .purchasing
                )
            }
            .buttonStyle(.boardPrimary)
            .disabled(store.state == .purchasing || selectedProduct == nil)

            Text(ctaCaption)
                .fontStyle(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Restore purchase") { Task { await store.restore() } }
                .fontStyle(.subheadline)
                .foregroundStyle(.primary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }

    private var ctaTitle: LocalizedStringKey {
        guard let product = selectedProduct else { return "Get First Class" }
        return product.hasIntroTrial ? "Start your free trial" : "Get First Class"
    }

    private var ctaCaption: String {
        guard let product = selectedProduct else { return "" }
        let renews = "then \(product.displayPrice)\(product.pricePeriod)"
        if let trial = product.trialDescription {
            return "\(trial), \(renews). Cancel anytime."
        }
        return "\(renews). Cancel anytime."
    }

    // MARK: Legal

    private var legalSection: some View {
        VStack(spacing: 8) {
            Text("Your subscription renews automatically until canceled. Manage or cancel anytime in your Apple ID settings.")
                .fontStyle(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://onboardapp.org/terms")!)
                Link("Privacy", destination: URL(string: "https://onboardapp.org/privacy")!)
            }
            .fontStyle(.caption)
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
    }

    // MARK: - Member (subscribed)

    private var memberBody: some View {
        VStack(spacing: 26) {
            heroSubtitleSlot

            perksSection

            Link(destination: URL(string: "itms-apps://apps.apple.com/account/subscriptions")!) {
                Text("Manage Subscription")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.boardPrimary)
            .padding(.horizontal, 20)

            legalSection
        }
    }

    /// One slot directly below the ticket, holding the celebration Host+bubble
    /// during the welcome and the static "You're flying First Class" title
    /// otherwise. Both are ALWAYS in the layout (so the slot never resizes/jumps)
    /// but only one is ever visible: the incoming element's fade-in is delayed
    /// by the outgoing element's fade-out duration, so they're strictly
    /// sequenced — no cross-fade frame where both are half-visible (which read as
    /// two overlapping messages). Nothing overlaps the ticket wordmark either;
    /// this sits cleanly below the pass.
    private var heroSubtitleSlot: some View {
        ZStack {
            Text("You're flying First Class. ✈️")
                .font(ButlerFont.medium(22))
                .multilineTextAlignment(.center)
                .opacity(showCelebration ? 0 : 1)
                .animation(.easeInOut(duration: 0.3).delay(showCelebration ? 0 : 0.32), value: showCelebration)
                .accessibilityHidden(showCelebration)

            celebrationBubble
                .opacity(showCelebration ? 1 : 0)
                .scaleEffect(showCelebration ? 1 : 0.92)
                .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(showCelebration ? 0.32 : 0), value: showCelebration)
                .accessibilityHidden(!showCelebration)
        }
        .padding(.horizontal, 24)
    }

    private var renewalNote: String? {
        if case .subscribed(let note) = store.state { return note }
        return nil
    }
}

// MARK: - Perk row

private struct PerkRow: View {
    let perk: FirstClassPerk
    let unlocked: Bool
    /// Drives this row's staggered entrance — flips true a beat after the
    /// previous row, so the list reveals top-to-bottom instead of all at once.
    let appeared: Bool
    let revealDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var isComingSoon: Bool { perk.availability == .comingSoon }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: unlocked && !isComingSoon ? "checkmark" : perk.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                // Butler, as this screen's one deliberate exception to the
                // system font — titles only; blurbs stay Zalando for legibility.
                Text(perk.title)
                    .font(ButlerFont.medium(17))
                Text(perk.blurb).fontStyle(.footnote)
            }

            Spacer(minLength: 8)

            if isComingSoon {
                Text("Soon")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
        }
        .opacity(isComingSoon ? 0.7 : 1)
        .opacity(reduceMotion ? 1 : (isVisible ? 1 : 0))
        .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(perk.title). \(perk.blurb)\(isComingSoon ? " Coming soon." : "")")
        .onChange(of: appeared, initial: true) { _, newValue in
            guard newValue, !isVisible else { return }
            withAnimation(.easeOut(duration: 0.3).delay(revealDelay)) { isVisible = true }
        }
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let product: FirstClassProduct
    let isSelected: Bool

    private var ink: Color { .primary }
    private var onInk: Color { Color(.systemBackground) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Always rendered (opacity-gated, not conditionally included) so
            // Monthly and Yearly reserve identical vertical space — the eyebrow
            // used to only exist on Yearly, making the two cards different heights.
            Text("BEST VALUE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(isSelected ? onInk : .primary)
                .opacity(product.isBestValue ? (isSelected ? 0.8 : 0.55) : 0)

            Text(product.plan.title)
                .font(ButlerFont.medium(22))
                .foregroundStyle(isSelected ? onInk : .primary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(product.displayPrice)
                    .fontStyle(.headline)
                Text(product.pricePeriod)
                    .fontStyle(.footnote)
                    .foregroundStyle(isSelected ? onInk.opacity(0.7) : .secondary)
            }
            .foregroundStyle(isSelected ? onInk : .primary)

            Text(product.trialDescription ?? " ")
                .fontStyle(.caption)
                .foregroundStyle(isSelected ? onInk.opacity(0.75) : .secondary)
                .opacity(product.trialDescription == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? ink : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1)
    }
}

#Preview {
    NavigationStack {
        FirstClassView()
            .environment(EntitlementStore(service: MockSubscriptionService()))
    }
}
