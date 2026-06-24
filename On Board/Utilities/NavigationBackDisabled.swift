//
//  NavigationBackDisabled.swift
//  On Board
//
//  Disables both the back button and the swipe-back gesture when active.
//  Used in edit modes to prevent accidental data loss.
//

import SwiftUI

extension View {
    /// Hides the navigation back button and disables the interactive
    /// swipe-back gesture when `disabled` is true.
    func navigationBackDisabled(_ disabled: Bool) -> some View {
        self
            .navigationBarBackButtonHidden(disabled)
            .background(InteractivePopGestureDisabler(disabled: disabled))
    }
}

private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    let disabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?
                .interactivePopGestureRecognizer?.isEnabled = !disabled
        }
    }
}
