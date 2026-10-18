import SwiftUI

enum LiberonsWebDestination {
    case home
    case privacy
    case terms
    case refunds
    case support

    func url(for language: LanguageStore.Language) -> URL? {
        let english = language == .english
        let path: String
        switch self {
        case .home:
            path = english ? "/en" : "/"
        case .privacy:
            path = english ? "/en/privacy" : "/privacy"
        case .terms:
            path = english ? "/en/terms" : "/terms"
        case .refunds:
            path = english ? "/en/refund-policy" : "/refund-policy"
        case .support:
            path = english ? "/en/support" : "/support"
        }
        return URL(string: "https://liberons.com\(path)")
    }
}

struct LiberonsExternalRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
