import SwiftUI
import UIKit

enum LiberonsTheme {
    /// Light keeps the subtle cool/lavender veil from the reference screenshot.
    /// Dark keeps the OLED canvas but uses elevated graphite surfaces so the same
    /// card hierarchy/framing remains visible instead of disappearing into black.
    static let canvasUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return .black
        }
        return UIColor(red: 0.965, green: 0.962, blue: 0.980, alpha: 1.0)
    }

    static let cardUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.105, green: 0.105, blue: 0.115, alpha: 1.0)
        }
        return .systemBackground
    }

    static let insetCardUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.155, green: 0.155, blue: 0.165, alpha: 1.0)
        }
        return .secondarySystemGroupedBackground
    }

    static var canvas: Color { Color(uiColor: canvasUIColor) }
    static var card: Color { Color(uiColor: cardUIColor) }
    static var insetCard: Color { Color(uiColor: insetCardUIColor) }

    static func configureGlobalAppearance() {
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear

        // Settings/List pages reached from Compte keep exactly the same hierarchy:
        // OLED/cool canvas outside, elevated rounded groups inside.
        UITableViewCell.appearance().backgroundColor = cardUIColor
        UICollectionViewCell.appearance().backgroundColor = cardUIColor

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

/// Use on the principal rounded blocks seen on Home, Backup, Library and Account.
struct LiberonsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LiberonsTheme.card)
    }
}

/// Use on metrics/cards nested inside a principal block.
struct LiberonsInsetSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LiberonsTheme.insetCard)
    }
}

extension View {
    func liberonsCanvas() -> some View { modifier(LiberonsCanvasModifier()) }
    func liberonsCardSurface() -> some View { modifier(LiberonsCardSurface()) }
    func liberonsInsetSurface() -> some View { modifier(LiberonsInsetSurface()) }
}
