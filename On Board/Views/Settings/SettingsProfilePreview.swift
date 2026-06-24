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
                Text(profile.displayName)
                    .fontStyle(.headline)
                    .foregroundStyle(.primary)
                Text("@\(profile.handle)")
                    .fontStyle(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.displayName), @\(profile.handle)")
        .accessibilityHint("View and edit your profile")
    }
}

#Preview {
    List {
        SettingsProfilePreview(profile: .currentUser)
    }
}
