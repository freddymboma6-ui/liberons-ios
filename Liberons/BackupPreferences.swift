import Foundation
import Combine

@MainActor
final class BackupPreferences: ObservableObject {
    static let choices = [10, 20, 50, 80, 100]

    @Published var backupPercent: Int {
        didSet { UserDefaults.standard.set(backupPercent, forKey: "liberons.backup.percent") }
    }

    @Published var removalPercent: Int {
        didSet { UserDefaults.standard.set(removalPercent, forKey: "liberons.removal.percent") }
    }

    init() {
        let savedBackup = UserDefaults.standard.integer(forKey: "liberons.backup.percent")
        let savedRemoval = UserDefaults.standard.integer(forKey: "liberons.removal.percent")
        backupPercent = Self.choices.contains(savedBackup) ? savedBackup : 100
        removalPercent = Self.choices.contains(savedRemoval) ? savedRemoval : 50
    }

    func selectedCount(total: Int) -> Int {
        min(total, Int(ceil(Double(total) * Double(backupPercent) / 100.0)))
    }

    func removableCount(protectedCount: Int) -> Int {
        min(protectedCount, Int(floor(Double(protectedCount) * Double(removalPercent) / 100.0)))
    }
}
