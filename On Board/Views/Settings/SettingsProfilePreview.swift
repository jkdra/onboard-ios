//
//  SettingsProfilePreview.swift
//  On Board
//

import SwiftUI

struct SettingsProfilePreview: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(profile: profile, size: .medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayNameOrHandle)
                    .fontStyle(.headline)
                    .foregroundStyle(.primary)
                if !profile.displayName.isEmpty {
                    Text(profile.handle)
                        .fontStyle(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            profile.displayName.isEmpty
                ? profile.displayNameOrHandle
                : "\(profile.displayNameOrHandle), \(profile.handle)"
        )
        .accessibilityHint("View and edit your profile")
    }
}

#Preview {
    List {
        SettingsProfilePreview(profile: .currentUser)
    }
}
