import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.autoupdatingCurrent,
            arguments: arguments
        )
    }

    static func duration(_ minutes: Int, compact: Bool = false) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = compact ? .abbreviated : .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(minutes * 60))
            ?? format("duration_minutes", minutes)
    }
}
