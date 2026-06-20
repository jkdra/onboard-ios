//
//  OnboardingProfileStepView.swift
//  On Board
//

import SwiftUI

struct OnboardingProfileStepView: View {
    @Environment(OnboardingStore.self) private var onboarding

    @State private var displayName = ""
    @State private var bio = ""
    @State private var avatarEmoji = "🌱"
    @FocusState private var focus: Field?

    private enum Field { case displayName, bio, emoji }

    private let emojiChoices = ["🌱", "✨", "🎓", "📌", "🎨", "🏀", "☕️", "🎧"]

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !onboarding.isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Display name", text: $displayName, axis: .vertical)
                        .fontStyle(.largeTitle)
                        .lineLimit(1...2)
                        .focused($focus, equals: .displayName)

                    TextField("A short bio (optional)", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .bio)
                        .fontStyle(.body)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Avatar")
                            .fontStyle(.subheadline)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(emojiChoices, id: \.self) { emoji in
                                    Button {
                                        avatarEmoji = emoji
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 32))
                                            .frame(width: 52, height: 52)
                                            .background(
                                                Circle()
                                                    .fill(avatarEmoji == emoji ? Color.accentColor.opacity(0.18) : Color.clear)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(avatarEmoji == emoji ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            await onboarding.submitProfile(
                                displayName: displayName,
                                bio: bio,
                                avatarEmoji: avatarEmoji
                            )
                        }
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(.boardPrimary)
                    .disabled(!canContinue)
                }
                .padding(20)
            }
            .background {
                ZStack {
                    Color.gray.opacity(0.08).ignoresSafeArea()
                    StripesOverlay(color: .primary, opacity: 0.05)
                }
            }
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if displayName.isEmpty {
                    displayName = onboarding.status?.displayName ?? ""
                }
                if bio.isEmpty {
                    bio = onboarding.status?.bio ?? ""
                }
                avatarEmoji = onboarding.status?.avatarEmoji ?? "🌱"
                focus = .displayName
            }
        }
    }
}

#Preview {
    OnboardingProfileStepView()
        .environment(OnboardingStore(
            service: MockOnboardingService(),
            auth: AuthStore(service: MockAuthService()),
            network: NetworkMonitor()
        ))
}
