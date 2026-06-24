//
//  SettingsView.swift
//  On Board
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("rotationEnabled") private var rotationEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss

    @State private var triggerShake = 0

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
                .animation(.smooth(duration: 0.2), value: rotationEnabled)
                .animation(.smooth(duration: 0.2), value: hapticsEnabled)
                .frame(maxWidth: .infinity)
                .mask { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom).padding(.top, -6) }
                .listRowBackground(Color.clear)
                .offset(y: 24)

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    Toggle("Card rotation", isOn: $rotationEnabled)
                } header: {
                    Text("Appearance")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("Change the look and feel of On Board to your liking.")
                        .fontStyle(.footnote)
                }

                Section {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                } header: {
                    Text("Feedback")
                        .fontStyle(.subheadline)
                } footer: {
                    Text("Light taps when you react to a post.")
                        .fontStyle(.footnote)
                }

                accountSection

                Section {
                    Link(destination: URL(string: "mailto:\(AppLinks.supportEmail)")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                } header: {
                    Text("Support")
                        .fontStyle(.subheadline)
                }

                Section {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        LabeledContent("Version", value: "\(version) (\(build))")
                    }
                    Text("Made with love by @jkdra")
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
            .fontStyle(.title3)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    shakeAndVibrate()
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
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(lineWidth: 6)
                            .frame(width: previewWidth / 2.8, height: previewHeight / 2.5)
                            .foregroundStyle(colors[index])
                            .rotationEffect(.degrees(rotationEnabled ? Double.random(in: -6...6) : 0))
                            .offset(x: index.isMultiple(of: 2) ? 4 : -4, y: index.isMultiple(of: 2) ? 0 : 48)
                    }
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

            NavigationLink {
                AccountSecuritySettingsView()
            } label: {
                Label("Security", systemImage: "lock.shield")
            }

            NavigationLink {
                AccountManagementSettingsView()
            } label: {
                Label("Account Management", systemImage: "person.crop.circle.badge.checkmark")
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
