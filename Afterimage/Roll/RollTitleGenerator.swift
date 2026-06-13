import Foundation

enum RollTitleGenerator {
    static func fallbackTitle(for date: Date = Date()) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
