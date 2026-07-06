//
//  SettingsIconBadge.swift
//  On Board
//
//  Rounded-square icon badge for settings list rows, matching the system
//  Settings app's icon treatment but in the app's monochrome language.
//

import SwiftUI

struct SettingsIconBadge: View {
    let systemImage: String
    var tint: Color = .primary

    // Scales with Dynamic Type so the badge stays proportional to the row's
    // text instead of looking undersized at accessibility text sizes.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.56, weight: .semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            // Purely decorative — the row's own text label carries the
            // accessible name, so VoiceOver shouldn't announce the icon too.
            .accessibilityHidden(true)
    }
}

/// Drop-in replacement for `Label(_:systemImage:)` in settings rows, pairing
/// `SettingsIconBadge` with the row's title.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemImage: systemImage, tint: tint)
            Text(title).fontStyle(.body)
        }
    }
}

#Preview {
    List {
        SettingsRowLabel(title: "Notification Settings", systemImage: "bell.badge.fill")
        SettingsRowLabel(title: "Contact Support", systemImage: "envelope.fill")
        SettingsRowLabel(title: "Delete Account", systemImage: "trash.fill", tint: .red)
    }
}
