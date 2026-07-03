import Foundation

enum RollTitleGenerator {
    static func nextDefaultTitle(defaults: UserDefaults = .standard) -> String {
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

    private static let nextRollNumberKey = "afterimage.nextRollNumber"

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
