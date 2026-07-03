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
    @AppStorage("rotationIntensity") private var rotationIntensity: Double = 0.6
    @Environment(\.dismiss) private var dismiss

    @State private var triggerShake = 0
    @State private var previewRotations: [Double] = [0, 0, 0, 0]

    private let previewWidth: CGFloat = 184
    private let previewHeight: CGFloat = 256
    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    private let colors: [Color] = [
        Color.purple, Color.blue, Color.green, Color.cyan
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
                            .tint(.primary)
                            .disabled(typeSize.isAccessibilitySize)
                        if typeSize.isAccessibilitySize {
                            Text("Card rotation is not available at accessibility text sizes.")
                                .fontStyle(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Appearance")
                        .fontStyle(.caption)
                } footer: {
                    Text("Change the look and feel of On Board to your liking.")
                        .fontStyle(.footnote)
                }

                Section {
                    Toggle(isOn: $hapticsEnabled) {
                        Text("Haptics").fontStyle(.body)
                    }
                    .tint(.primary)
                } header: {
                    Text("Feedback")
                        .fontStyle(.caption)
                } footer: {
                    Text("Light taps when you react to a post.")
                        .fontStyle(.footnote)
                }

                Section {
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("Notification Settings", systemImage: "bell.badge")
                            .fontStyle(.body)
                    }
                } header: {
                    Text("Notifications")
                        .fontStyle(.caption)
                } footer: {
                    Text("Manage alerts for new boards and clearing reminders in iOS Settings.")
                        .fontStyle(.footnote)
                }

                accountSection

                Section {
                    Link(destination: URL(string: "mailto:\(AppLinks.supportEmail)")!) {
                        Label("Contact Support", systemImage: "envelope")
                            .fontStyle(.body)
                    }
                    Link(destination: AppLinks.reportMailURL) {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                            .fontStyle(.body)
                    }
                } header: {
                    Text("Support")
                        .fontStyle(.caption)
                }

                Section {
                    Link(destination: AppLinks.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .fontStyle(.body)
                    }
                    Link(destination: AppLinks.termsOfServiceURL) {
                        Label("Terms of Service", systemImage: "doc.text")
                            .fontStyle(.body)
                    }
                } header: {
                    Text("Legal")
                        .fontStyle(.caption)
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
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    shakeAndVibrate()
                }
            }
            .onAppear {
                previewRotations = (0..<4).map { _ in Double.random(in: -6...6) }
            }
            .onChange(of: rotationIntensity) { oldValue, newValue in
                if oldValue == 0 && newValue > 0 {
                    previewRotations = (0..<4).map { _ in Double.random(in: -6...6) }
                }
            }
            .onChange(of: hapticsEnabled) { _, on in
                if on { shakeAndVibrate() }
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                guard !isSignedIn else { return }
                dismiss()
            }
        }
    }

    // MARK: - Board preview

    private var boardPreview: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 48, topTrailing: 48))
            .stroke(lineWidth: 6)
            .frame(width: previewWidth, height: previewHeight)
            .foregroundStyle(.tertiary)
            .overlay(alignment: .bottom) {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 14) {
                        ForEach(0..<2) { index in
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(lineWidth: 6)
                                .frame(width: previewWidth * 0.6, height: previewHeight / 2.5)
                                .foregroundStyle(colors[index])
                        }
                    }
                    .padding(.bottom, 16)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<4) { index in
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(lineWidth: 6)
                                .frame(width: previewWidth / 2.8, height: previewHeight / 2.5)
                                .foregroundStyle(colors[index])
                                .rotationEffect(.degrees(previewRotations[index] * rotationIntensity))
                                .offset(x: index.isMultiple(of: 2) ? 4 : -4, y: index.isMultiple(of: 2) ? 0 : 48)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if typeSize.isAccessibilitySize {
                    Image(systemName: "accessibility")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
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

            if onboarding.status?.waitlistJoinedAt != nil {
                Label("On the waitlist", systemImage: "clock.badge.checkmark")
                    .fontStyle(.body)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                AccountSecuritySettingsView()
            } label: {
                Label("Security", systemImage: "lock.shield")
                    .fontStyle(.body)
            }

            NavigationLink {
                AccountManagementSettingsView()
            } label: {
                Label("Account Management", systemImage: "person.crop.circle.badge.checkmark")
                    .fontStyle(.body)
            }
        } header: {
            Text("Account")
                .fontStyle(.caption)
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
            let (w, h) = (size.width, size.height)
            var path = Path()
            path.move(to:    CGPoint(x: w * 0.5, y: 0))
            path.addLine(to: CGPoint(x: w,       y: h * 0.2))
            path.addLine(to: CGPoint(x: 0,       y: h * 0.4))
            path.addLine(to: CGPoint(x: w,       y: h * 0.6))
            path.addLine(to: CGPoint(x: 0,       y: h * 0.8))
            path.addLine(to: CGPoint(x: w * 0.5, y: h))
            ctx.stroke(path, with: .foreground, lineWidth: 3)
        }
        .frame(width: 14, height: 44)
    }
}

#Preview {
    SettingsView()
        .environment(AuthStore(service: MockAuthService()))
        .environment(BoardStore.sampleBoard(currentUserID: SampleProfileID.maya))
}
