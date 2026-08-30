import Foundation

enum RollTitleGenerator {
    static func nextDefaultTitle(defaults: UserDefaults = .standard) -> String {
        migrateLegacyRollNumberIfNeeded(defaults: defaults)
        let rollNumber = max(defaults.integer(forKey: nextRollNumberKey), 1)
        defaults.set(rollNumber + 1, forKey: nextRollNumberKey)
        return formattedRollTitle(for: rollNumber)
    }

    static func fallbackTitle(for date: Date = Date()) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static func formattedRollTitle(for number: Int) -> String {
        if number < 1_000 {
            return "Roll \(String(format: "%03d", number))"
        }

        return "Roll \(number)"
    }

    private static let nextRollNumberKey = "nine.nextRollNumber"
    private static let legacyNextRollNumberKey = "afterimage.nextRollNumber"

    private static func migrateLegacyRollNumberIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: nextRollNumberKey) == nil,
              let legacyNumber = defaults.object(forKey: legacyNextRollNumberKey) as? Int else {
            return
        }

        defaults.set(legacyNumber, forKey: nextRollNumberKey)
        defaults.removeObject(forKey: legacyNextRollNumberKey)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
