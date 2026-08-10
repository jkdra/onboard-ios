//
//  ProfileReadContent.swift
//  On Board
//
//  Read-mode half of the profile screen. ProfileView owns the edit/read
//  switch and the namespace; this view just renders into it. Matched-geometry
//  IDs are shared with ProfileEditContent via ProfileGeometryID, so the
//  in-place morph between modes is untouched by the split.
//

import SwiftUI

/// Matched-geometry contract between the read and edit halves of the profile
/// screen. One enum, both sides — a typo can't silently break a morph.
enum ProfileGeometryID: Hashable {
    case displayName
    case username
    case bio
    case popScore
    case favoriteColor
    case actionButton
    case avatarImage
}

struct ProfileReadContent: View {
    let profile: Profile
    let namespace: Namespace.ID
    let isAvatarViewerOpen: Bool
    let isUpdatingBlock: Bool
    let onEditProfile: () -> Void
    let onAvatarTap: () -> Void
    let onUnblock: () -> Void
    var celebrateBirthday: Bool = false
    var onTestBirthday: (() -> Void)? = nil

    @Environment(BoardStore.self) private var store
    @Environment(\.favoriteColorEnabled) private var favoriteColorEnabled

    private var canEdit: Bool { store.canEdit(profile: profile) }
    private var isBlockedByMe: Bool { store.isBlocked(userID: profile.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                avatar
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .fontStyle(.body)
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: ProfileGeometryID.bio, in: namespace, anchor: .leading)
            }

            ProfileMetaRow(profile: profile, showsBirthday: !isBlockedByMe, celebrateBirthday: celebrateBirthday)

            // Mock-only: preview the birthday celebration on demand.
            if !AppConfiguration.current.isSupabaseConfigured, let onTestBirthday {
                Button("Test Birthday 🎂 [DEV]", action: onTestBirthday)
                    .fontStyle(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !isBlockedByMe {
                if let popScore = store.popScore(for: profile.id) {
                    PopScoreView(score: popScore)
                        .padding(.top, 8)
                        .matchedGeometryEffect(id: ProfileGeometryID.popScore, in: namespace)
                } else {
                    // Skeleton at the real PopScoreView geometry (header, 12pt
                    // bar, caption row) so the loaded bar replaces it without
                    // the slot changing size.
                    popScoreSkeleton
                        .padding(.top, 8)
                        .matchedGeometryEffect(id: ProfileGeometryID.popScore, in: namespace)
                }

                // Dark-deployed (FeatureFlag.favoriteColor). No skeleton: a
                // user who hasn't earned a favorite yet shows nothing at all,
                // so a placeholder here would promise a row that may never
                // arrive.
                if favoriteColorEnabled, let favorite = store.favoriteTone(for: profile.id) {
                    FavoriteColorView(favorite: favorite)
                        .padding(.top, 14)
                        .matchedGeometryEffect(id: ProfileGeometryID.favoriteColor, in: namespace)
                }
            }

            if canEdit {
                actionButton("Edit Profile", systemImage: "pencil", style: .boardSecondary, action: onEditProfile)
            } else if isBlockedByMe {
                actionButton("Unblock", systemImage: "hand.raised.slash", style: .boardSecondary, action: onUnblock)
                    .disabled(isUpdatingBlock)
            } else {
                followButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popScoreSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pop Score")
                .fontStyle(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            SkeletonShape(shape: Capsule())
                .frame(height: 12)
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonShape(shape: Capsule())
                        .frame(width: 44, height: 14)
                }
            }
        }
    }

    private var avatar: some View {
        Button(action: onAvatarTap) {
            AvatarView(profile: profile, size: .large)
                .background {
                    // Same handoff as the post image: exactly one live source
                    // per id at steady state, or the viewer's close morph can
                    // resolve against a stale frame.
                    Color.clear.matchedGeometryEffect(
                        id: ProfileGeometryID.avatarImage, in: namespace, isSource: !isAvatarViewerOpen
                    )
                }
                .opacity(isAvatarViewerOpen ? 0 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.displayName) avatar")
    }

    @ViewBuilder
    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Display name is optional. When absent, promote the handle into the
            // title slot instead of leaving a blank title line above it. It keeps
            // the `.username` id (not `.displayName`) so entering edit mode morphs
            // it smoothly into the now-secondary username field; the empty
            // display-name field simply fades in above it, which reads as "you can
            // add one" rather than a glitchy content swap.
            if profile.displayName.isEmpty {
                Text(profile.displayNameOrHandle)
                    .fontStyle(.title)
                    .fontWeight(.heavy)
                    .matchedGeometryEffect(id: ProfileGeometryID.username, in: namespace, anchor: .leading)
            } else {
                Text(profile.displayNameOrHandle)
                    .fontStyle(.title)
                    .fontWeight(.heavy)
                    .matchedGeometryEffect(id: ProfileGeometryID.displayName, in: namespace, anchor: .leading)
                Text(profile.handle)
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
                    .matchedGeometryEffect(id: ProfileGeometryID.username, in: namespace, anchor: .leading)
            }
        }
    }

    private var followButton: some View {
        let isFollowing = store.followedUserIDs.contains(profile.id)
        return Button {
            if isFollowing {
                store.unfollowUser(id: profile.id)
            } else {
                store.followUser(id: profile.id)
            }
        } label: {
            Label(
                isFollowing ? "Following" : "Follow",
                systemImage: isFollowing ? "person.fill.checkmark" : "person.badge.plus"
            )
        }
        .buttonStyle(isFollowing ? .boardSecondary : .boardPrimary)
        .padding(.top, 8)
        .matchedGeometryEffect(id: ProfileGeometryID.actionButton, in: namespace)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        style: BoardButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(style)
        .padding(.top, 8)
        .matchedGeometryEffect(id: ProfileGeometryID.actionButton, in: namespace)
    }
}

/// "joined <date> [· birthday]" — shown in both read and edit mode.
struct ProfileMetaRow: View {
    let profile: Profile
    let showsBirthday: Bool
    /// When it's their birthday (and they share it), the birthday line
    /// cross-fades to "Happy Birthday!" and back once.
    var celebrateBirthday: Bool = false

    @State private var greetingActive = false
    @State private var greetingOpacity: Double = 1

    private static let joinedFormatter: Date.FormatStyle = .dateTime
        .month(.wide)
        .day()
        .year()

    /// Month + day only — never the year. `showBirthday` opts into displaying
    /// the day people can wish them happy birthday, not their age.
    private var formattedBirthday: String? {
        guard let raw = profile.birthday else { return nil }
        guard let date = ProfileDraft.birthdayFormatter.date(from: raw) else { return nil }
        return date.formatted(.dateTime.month(.wide).day())
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(
                "joined \(profile.joinedAt.formatted(Self.joinedFormatter).lowercased())",
                systemImage: "calendar"
            )
            if showsBirthday, profile.showBirthday, let birthday = formattedBirthday {
                Text("•")
                Label(greetingActive ? "Happy Birthday!" : birthday.lowercased(), systemImage: "birthday.cake")
                    .opacity(greetingOpacity)
            }
        }
        .fontStyle(.footnote)
        .foregroundStyle(.secondary)
        .task(id: celebrateBirthday) {
            guard celebrateBirthday else { return }
            await runBirthdayGreeting()
        }
    }

    /// Finite there-and-back: "august 12" → 0 → "Happy Birthday!" → hold → 0 → back.
    private func runBirthdayGreeting() async {
        func fade(to value: Double) { withAnimation(.easeInOut(duration: 0.4)) { greetingOpacity = value } }
        func swap(_ on: Bool) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { greetingActive = on }
        }
        fade(to: 0)
        try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }
        swap(true); fade(to: 1)
        try? await Task.sleep(for: .milliseconds(2600)); guard !Task.isCancelled else { return }
        fade(to: 0)
        try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }
        swap(false); fade(to: 1)
    }
}
