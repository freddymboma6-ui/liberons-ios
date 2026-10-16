import Foundation
import Combine

@MainActor
final class BackupPreferences: ObservableObject {
    enum BackupOrder: String, CaseIterable, Identifiable {
        case oldest
        case newest
        var id: String { rawValue }
    }

    static let choices = [10, 20, 50, 80, 100]

    @Published var backupPercent: Int {
        didSet { UserDefaults.standard.set(backupPercent, forKey: "liberons.backup.percent") }
    }

    @Published var removalPercent: Int {
        didSet { UserDefaults.standard.set(removalPercent, forKey: "liberons.removal.percent") }
    }

    @Published var backupOrder: BackupOrder {
        didSet { UserDefaults.standard.set(backupOrder.rawValue, forKey: "liberons.backup.order") }
    }

    init() {
        let savedBackup = UserDefaults.standard.integer(forKey: "liberons.backup.percent")
        let savedRemoval = UserDefaults.standard.integer(forKey: "liberons.removal.percent")
        backupPercent = Self.choices.contains(savedBackup) ? savedBackup : 100
        removalPercent = Self.choices.contains(savedRemoval) ? savedRemoval : 50
        backupOrder = BackupOrder(rawValue: UserDefaults.standard.string(forKey: "liberons.backup.order") ?? "") ?? .oldest
    }

    func selectedCount(total: Int) -> Int {
        min(total, Int(ceil(Double(total) * Double(backupPercent) / 100.0)))
    }

    func removableCount(protectedCount: Int) -> Int {
        guard protectedCount > 0 else { return 0 }
        return min(protectedCount, max(1, Int(ceil(Double(protectedCount) * Double(removalPercent) / 100.0))))
    }
}
