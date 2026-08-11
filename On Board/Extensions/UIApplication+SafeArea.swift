//
//  UIApplication+SafeArea.swift
//  On Board
//
//  Key-window safe-area insets, used by PostImageCropView and
//  ProfileImageCropView to lay out full-bleed crop content behind the
//  translucent bars.
//

import UIKit

extension UIApplication {
    var safeAreaInsets: UIEdgeInsets {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}
