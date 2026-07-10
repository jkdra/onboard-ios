//
//  WeeklyPromptBanner.swift
//  On Board
//

import SwiftUI

struct WeeklyPromptBanner: View {
    @Environment(BoardStore.self) private var store
    @AppStorage("profanityEnabled") private var profanityEnabled = false

    private var currentPromptText: String {
        guard let week = store.activeBoardWeek else {
            return "No prompt this week! Get creative!"
        }
        if profanityEnabled, let profane = week.promptProfane, !profane.trimmed.isEmpty {
            return profane
        } else if let clean = week.promptClean, !clean.trimmed.isEmpty {
            return clean
        }
        return "No prompt this week! Get creative!"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Image("OBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                // Removed the circle clipping so the raw PDF character is shown.

            VStack(alignment: .leading, spacing: 4) {
                Text("The Host")
                    .fontStyle(.caption2)
                    .fontWeight(.black)
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)
                
                Text(currentPromptText)
                    .fontStyle(.callout)
                    .foregroundStyle(.primary)
            }
            .padding(14)
            .background {
                let bubbleShape = UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16
                )
                
                bubbleShape
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .primary.opacity(0.15), radius: 0, x: 4, y: 4) // Hard comic-style shadow
                    .overlay(
                        bubbleShape.stroke(Color.primary, lineWidth: 2.5) // Thick outline matching the logo
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
