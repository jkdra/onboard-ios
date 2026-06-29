//
//  NavigationBarAppearance.swift
//  On Board
//
//  Global navigation bar styling. Call once from the app entry point.
//  Scroll-edge stays transparent at the top; the bar material fades in
//  once content scrolls underneath.
//

import UIKit

enum NavigationBarAppearance {
    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        let largeTitleFont = UIFont(name: "ZalandoSansExpanded-ExtraBold", size: 28)
            ?? UIFont.systemFont(ofSize: 28, weight: .bold)
        let titleFont = UIFont(name: "ZalandoSansExpanded-Bold", size: 14)
            ?? UIFont.systemFont(ofSize: 16, weight: .medium)
        let buttonFont = UIFont(name: "ZalandoSansExpanded-Regular", size: 14)
            ?? UIFont.systemFont(ofSize: 16, weight: .regular)

        func applyFonts(to appearance: UINavigationBarAppearance) {
            appearance.largeTitleTextAttributes = [.font: largeTitleFont]
            appearance.titleTextAttributes = [.font: titleFont]

            let buttonAppearance = UIBarButtonItemAppearance()
            buttonAppearance.normal.titleTextAttributes = [.font: buttonFont, .foregroundColor: UIColor.label]
            appearance.buttonAppearance = buttonAppearance
        }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        applyFonts(to: standard)

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        applyFonts(to: scrollEdge)

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = standard
        navigationBar.compactAppearance = standard
        navigationBar.scrollEdgeAppearance = scrollEdge

        UIView.appearance().tintColor = UIColor(named: "AccentColor")

        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: titleFont, .foregroundColor: UIColor.label],
            for: .normal
        )
    }
}
