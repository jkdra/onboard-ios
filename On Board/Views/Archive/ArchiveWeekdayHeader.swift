//
//  ArchiveWeekdayHeader.swift
//  On Board
//
//  Mon–Sun row pinned below the archive navigation bar.
//

import SwiftUI

struct ArchiveWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ArchiveCalendarBuilder.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .fontStyle(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Days of the week")
    }
}

/// Material on iOS 18+, navigation-style gradient on iOS 26+.
struct ArchiveToolbarChrome: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.88),
                    Color(.systemBackground).opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}

/// Bottom inset chrome — gradient fades upward on iOS 26+.
struct ArchiveBottomToolbarChrome: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.55),
                    Color(.systemBackground).opacity(0.88),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ArchiveWeekdayHeader()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background { ArchiveToolbarChrome() }
        Spacer()
    }
}
