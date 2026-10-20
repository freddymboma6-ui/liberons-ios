import SwiftUI

struct BrandLogoView: View {
    var height: CGFloat = 52
    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Libérons")
    }
}
