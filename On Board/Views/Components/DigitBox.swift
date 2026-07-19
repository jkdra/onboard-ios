//
//  DigitBox.swift
//  On Board
//

import SwiftUI

/// Single rounded-rectangle digit cell used by `OTPCodeField`.
struct DigitBox: View {
    var character: String
    var isActive: Bool = false
    var width: CGFloat = 36
    var height: CGFloat = 42

    var body: some View {
        Text(character)
            .fontStyle(.title2)
            .monospacedDigit()
            .frame(width: width, height: height)
            .background {
                GlassBackground(
                    shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                    fallback: AnyShapeStyle(.thinMaterial)
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive ? Color.primary : Color.secondary.opacity(0.25),
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
}
