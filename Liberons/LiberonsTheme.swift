import SwiftUI
import UIKit

enum LiberonsTheme {
    static let canvasUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark { return .black }
        return UIColor(red: 0.965, green: 0.962, blue: 0.980, alpha: 1.0)
    }

    static let cardUIColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.105, green: 0.105, blue: 0.110, alpha: 1.0)
        }
        return .systemBackground
    }

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
        // Keep the custom canvas, but let SwiftUI own List rows, headers and footers.
        // A global UITableViewCell/UICollectionViewCell background also colors
        // supplementary section content, which breaks grouped cards in light/dark.
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
