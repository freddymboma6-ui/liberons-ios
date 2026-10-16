import SwiftUI
import UIKit

enum LiberonsTheme {
    /// Very subtle cool/lavender canvas in Light Mode, deep OLED black in Dark Mode.
    /// This mirrors the visual treatment used on the Libérons dashboard while keeping
    /// cards, materials and system controls fully adaptive.
    static let canvasUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return .black
        }
        return UIColor(
            red: 0.965,
            green: 0.962,
            blue: 0.980,
            alpha: 1.0
        )
    }

    static var canvas: Color {
        Color(uiColor: canvasUIColor)
    }

    static func configureGlobalAppearance() {
        // SwiftUI List/Form are backed by UIKit containers on iOS. Making their
        // outer canvas transparent lets the same Libérons background continue
        // through Settings, Privacy, Notifications, Help and other secondary pages.
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear

        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.backgroundColor = .clear
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
    }
}

private struct LiberonsCanvasModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LiberonsTheme.canvas.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func liberonsCanvas() -> some View {
        modifier(LiberonsCanvasModifier())
    }
}
