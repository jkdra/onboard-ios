//
//  CropAspectOption.swift
//  On Board
//
//  Aspect-ratio presets for PostImageCropView's rectangular crop tool.
//

import Foundation

enum CropAspectOption: CaseIterable, Identifiable, Equatable {
    case free, square, ratio4x5, ratio16x9, original

    var id: Self { self }

    /// Base numeric ratio (width / height) before orientation is applied.
    /// `nil` for options with no fixed ratio (`.free`) or ones resolved
    /// dynamically against the source image (`.original`).
    var baseRatio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .ratio4x5: return 4.0 / 5.0
        case .ratio16x9: return 16.0 / 9.0
        case .original: return nil
        }
    }

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .ratio4x5: return "4:5"
        case .ratio16x9: return "16:9"
        case .original: return "Original"
        }
    }

    /// Whether this option has a meaningful portrait/landscape distinction.
    /// Square is symmetric, Free has no fixed ratio, and Original always
    /// matches the source image's own orientation — none of those benefit
    /// from an independent orientation flip.
    var supportsOrientationToggle: Bool {
        switch self {
        case .ratio4x5, .ratio16x9: return true
        case .free, .square, .original: return false
        }
    }
}
