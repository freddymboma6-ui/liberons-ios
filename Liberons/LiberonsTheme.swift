import SwiftUI
import UIKit

enum LiberonsTheme {
    static let canvasUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .black }
        return UIColor(red: 0.965, green: 0.962, blue: 0.980, alpha: 1.0)
    }

    // Principal white cards in Light Mode become clearly separated graphite cards
    // in Dark Mode while preserving exactly the same layout/framing.
    static let cardUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.105, green: 0.105, blue: 0.110, alpha: 1.0)
        }
        return .systemBackground
    }

    // Small metric blocks nested in a principal card get one additional elevation.
    static let insetCardUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.145, green: 0.145, blue: 0.155, alpha: 1.0)
        }
        return .secondarySystemGroupedBackground
    }

    static var canvas: Color { Color(uiColor: canvasUIColor) }
    static var card: Color { Color(uiColor: cardUIColor) }
    static var insetCard: Color { Color(uiColor: insetCardUIColor) }

    static func configureGlobalAppearance() {
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear

        // Keep native grouped pages under Account visually consistent with the
        // rounded-card hierarchy used on Home/Backup/Library/Account.
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

extension View {
    func liberonsCanvas() -> some View {
        modifier(LiberonsCanvasModifier())
    }
}
