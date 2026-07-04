//
//  NavigationBarAppearance.swift
//  On Board
//
//  Global navigation bar styling. Call once from the app entry point.
//  Scroll-edge stays transparent at the top; the bar material fades in
//  once content scrolls underneath.
//

import UIKit
import SwiftUI

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
            buttonAppearance.normal.titleTextAttributes = [.font: buttonFont]
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

        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: titleFont, .foregroundColor: UIColor.label],
            for: .normal
        )
        
        // Changes the background color when the toggle is ON
        UISwitch.appearance().onTintColor = UIColor(named: "AccentColor")
        
        // Changes the color of the circular knob (the "thumb") itself to match the system background!
        UISwitch.appearance().thumbTintColor = .systemBackground
    }
}
