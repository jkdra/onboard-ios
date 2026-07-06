//
//  SettingsView.swift
//  On Board
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("profanityFilterEnabled") private var profanityFilterEnabled: Bool = true
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.7
    @Environment(\.dismiss) private var dismiss

    @State private var triggerShake = 0
    @State private var previewRotations: [Double] = (0..<4).map { _ in Double.random(in: -6...6) }
    @State private var showProfanityInfo = false
    @State private var webDocument: WebDocument?

    private let previewWidth: CGFloat = 184
    private let previewHeight: CGFloat = 256
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    var body: some View {
        NavigationStack {
            Form {
                HStack(alignment: .center) {
                    Spacer()
                    ZigZagMark()
                        .opacity(hapticsEnabled ? 1 : 0)
                    Spacer()
                    boardPreview
                        .keyframeAnimator(initialValue: CGFloat(0), trigger: triggerShake) { content, offset in
                            content.offset(x: offset)
                        } keyframes: { _ in
                            LinearKeyframe(3,  duration: 0.05)
                            LinearKeyframe(-6, duration: 0.05)
                            LinearKeyframe(6,  duration: 0.05)
                            LinearKeyframe(-6, duration: 0.05)
                            LinearKeyframe(3,  duration: 0.05)
                            LinearKeyframe(0,  duration: 0.05)
                        }

                    Spacer()
                    ZigZagMark()
                        .opacity(hapticsEnabled ? 1 : 0)
                    Spacer()
                }
                .animation(.smooth(duration: 0.2), value: rotationIntensity)
                .animation(.smooth(duration: 0.2), value: hapticsEnabled)
                .frame(maxWidth: .infinity)
                .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom).padding(.top, -6) }
                .listRowBackground(Color.clear)
                .offset(y: 24)

                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    } label: {
                        Text("Theme").fontStyle(.body)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Card rotation").fontStyle(.body)
                            Spacer()
                            Text(rotationIntensity == 0 || typeSize.isAccessibilitySize ? "Off" : "\(Int(rotationIntensity * 100))%")
                                .foregroundStyle(.secondary)
                                .fontStyle(.footnote)
                                .monospacedDigit()
                        }
                        Slider(value: $rotationIntensity, in: 0...1, step: 0.05)
                            .disabled(typeSize.isAccessibilitySize)
                        if typeSize.isAccessibilitySize {
                            Text("Card rotation is not available at accessibility text sizes.")
                                .fontStyle(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Toggle(isOn: $hapticsEnabled) {
                        Text("Haptics").fontStyle(.body)
                    }
                    .tint(.primary)
                    
                    Toggle(isOn: $profanityFilterEnabled) {
                        HStack(spacing: 6) {
                            Text("Profanity").fontStyle(.body)
                            Button {
                                showProfanityInfo = true
                            } label: {
                                Image(systemName: "info.circle.fill")
                                    .fontStyle(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .tint(.primary)
                    .alert("Profanity", isPresented: $showProfanityInfo) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("Mild profanity may be used in weekly prompts and in-app communications for a more... informal experience. This setting does not affect user-generated content that may contain profanity.")
                    }
                    .tint(.primary)
                } header: {
                    Text("User Experience")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("Customize the look, feel, and content of On Board.")
                        .fontStyle(.footnote)
                }

                accountSection

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Notification Settings", systemImage: "bell.badge.fill")
                    }
                } header: {
                    Text("Notifications")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("Manage which notifications you want to receive.")
                        .fontStyle(.footnote)
                }

                Section {
                    Link(destination: URL(string: "mailto:\(AppLinks.supportEmail)")!) {
                        SettingsRowLabel(title: "Contact Support", systemImage: "envelope.fill")
                    }
                    Link(destination: AppLinks.reportMailURL) {
                        SettingsRowLabel(title: "Report a Problem", systemImage: "exclamationmark.bubble.fill")
                    }
                } header: {
                    Text("Support")
                        .fontStyle(.subheadline)
                }

                Section {
                    legalLinkRow(
                        title: "Privacy Policy",
                        systemImage: "hand.raised.fill",
                        url: AppLinks.privacyPolicyURL
                    )
                    legalLinkRow(
                        title: "Terms of Service",
                        systemImage: "doc.text.fill",
                        url: AppLinks.termsOfServiceURL
                    )
                } header: {
                    Text("Legal")
                        .fontStyle(.subheadline)
                }

                Section {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        LabeledContent {
                            Text("\(version) (\(build))").fontStyle(.body)
                        } label: {
                            Text("Version").fontStyle(.body)
                        }
                    }
                    Text("Made with love by @jkdra")
                        .fontStyle(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            .onChange(of: rotationIntensity) { oldValue, newValue in
                if oldValue == 0 && newValue > 0 { previewRotations = (0..<4).map { _ in Double.random(in: -6...6) } }
            }
            .onChange(of: hapticsEnabled) { _, on in if on { shakeAndVibrate() } }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                guard !isSignedIn else { return }
                dismiss()
            }
            .sheet(item: $webDocument) { document in
                WebContentSheet(document: document)
            }
        }
    }

    // MARK: - Legal links

    private func legalLinkRow(title: String, systemImage: String, url: URL) -> some View {
        Button {
            webDocument = WebDocument(title: title, url: url)
        } label: {
            HStack(spacing: 12) {
                SettingsIconBadge(systemImage: systemImage)
                Text(title).fontStyle(.body)
                Spacer(minLength: 8)
                // Signals this row shows external (web) content, even though
                // it opens in-app rather than handing off to Safari.
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityHint("Opens in a web view")
    }

    // MARK: - Board preview

    private var boardPreview: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48))
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48))
                    .stroke(.quaternary, lineWidth: 6)
            }
            .frame(width: previewWidth, height: previewHeight)
            .overlay(alignment: .top) {
                Text("\"camera\"")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
            }
            .overlay(alignment: .bottom) {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 14) {
                        ForEach(0..<2, id: \.self) { index in
                            PreviewCard(
                                index: index,
                                rotation: 0,
                                width: previewWidth * 0.85,
                                height: previewHeight / 2.5,
                                triggerShake: triggerShake,
                                hapticsEnabled: hapticsEnabled,
                                isMasonry: false
                            )
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<4, id: \.self) { index in
                            PreviewCard(
                                index: index,
                                rotation: previewRotations[index] * rotationIntensity,
                                width: previewWidth / 2.8,
                                height: previewHeight / 2.5,
                                triggerShake: triggerShake,
                                hapticsEnabled: hapticsEnabled,
                                isMasonry: true
                            )
                        }
                    }
                }
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48)))
            .overlay(alignment: .topTrailing) {
                if typeSize.isAccessibilitySize {
                    Image(systemName: "accessibility")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .padding(4)
                        .background(.primary, in: .circle)
                        .offset(x: 4, y: -4)
                }
            }
    }

    // MARK: - Haptics

    private func shakeAndVibrate() {
        triggerShake += 1
        guard hapticsEnabled else { return }
        let hard = UIImpactFeedbackGenerator(style: .rigid)
        let soft = UIImpactFeedbackGenerator(style: .light)
        hard.prepare()
        soft.prepare()
        hard.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            soft.impactOccurred(intensity: 0.8)
        }
        previewRotations = (0..<4).map { _ in Double.random(in: -6...6) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            soft.impactOccurred(intensity: 0.5)
        }
    }

    // MARK: - Account section

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let profile = store.currentUser {
                NavigationLink {
                    ProfileView(profile: profile, presentation: .navigation)
                } label: {
                    SettingsProfilePreview(profile: profile)
                }
            }



            NavigationLink {
                AccountSecuritySettingsView()
            } label: {
                SettingsRowLabel(title: "Security", systemImage: "lock.shield.fill")
            }

            NavigationLink {
                AccountManagementSettingsView()
            } label: {
                SettingsRowLabel(title: "Account Management", systemImage: "person.crop.circle.fill.badge.checkmark")
            }

            NavigationLink {
                BlockedUsersSettingsView()
            } label: {
                SettingsRowLabel(title: "Blocked Users", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Account")
                .fontStyle(.subheadline)
        } footer: {
            if store.currentUser == nil {
                Text("Your profile will appear here once your board data loads.")
                    .fontStyle(.footnote)
            }
        }
    }
}

// MARK: - Zig-zag haptic indicator

private struct ZigZagMark: View {
    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 2.0
            let w = size.width - (inset * 2)
            let h = size.height - (inset * 2)
            
            var path = Path()
            path.move(to:    CGPoint(x: inset + w * 0.5, y: inset))
            path.addLine(to: CGPoint(x: inset + w,       y: inset + h * 0.2))
            path.addLine(to: CGPoint(x: inset,           y: inset + h * 0.4))
            path.addLine(to: CGPoint(x: inset + w,       y: inset + h * 0.6))
            path.addLine(to: CGPoint(x: inset,           y: inset + h * 0.8))
            path.addLine(to: CGPoint(x: inset + w * 0.5, y: inset + h))
            
            ctx.stroke(path, with: .foreground, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 14, height: 44)
    }
}

#Preview {
    SettingsView()
        .environment(AuthStore(service: MockAuthService()))
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}

// MARK: - Preview Card

private struct PreviewCard: View {
    let index: Int
    let rotation: Double
    let width: CGFloat
    let height: CGFloat
    let triggerShake: Int
    let hapticsEnabled: Bool
    let isMasonry: Bool
    
    private let colors: [Color] = [.orange, .mint, .pink, .cyan]
    
    var body: some View {
        let color = colors[index % colors.count]
        
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(color.opacity(0.2))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(0.8), lineWidth: 2)
            }
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .keyframeAnimator(initialValue: Double(0), trigger: triggerShake) { content, wobble in
                content.rotationEffect(.degrees(hapticsEnabled ? wobble : 0))
            } keyframes: { _ in
                // Add a small playful wobble to each card independently
                CubicKeyframe(index.isMultiple(of: 2) ? 6 : -6, duration: 0.1)
                CubicKeyframe(index.isMultiple(of: 2) ? -4 : 4, duration: 0.12)
                CubicKeyframe(index.isMultiple(of: 2) ? 2 : -2, duration: 0.12)
                CubicKeyframe(0, duration: 0.1)
            }
            // Fake masonry layout: right column pushed down
            .offset(
                x: isMasonry ? (index.isMultiple(of: 2) ? 4 : -4) : 0,
                y: isMasonry ? (index.isMultiple(of: 2) ? 0 : 48) : 0
            )
    }
}
