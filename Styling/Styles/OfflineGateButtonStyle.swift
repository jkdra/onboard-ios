//
//  OfflineGateButtonStyle.swift
//  On Board
//
//  Angular outline button for the offline / BSOD gate screen.
//

import SwiftUI

struct OfflineGateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                Rectangle()
                    .fill(configuration.isPressed ? Color.white.opacity(0.18) : .clear)
            }
            .overlay {
                Rectangle()
                    .strokeBorder(.white, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == OfflineGateButtonStyle {
    static var offlineGate: OfflineGateButtonStyle { OfflineGateButtonStyle() }
}
