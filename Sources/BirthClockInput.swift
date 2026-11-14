import Foundation

/// UI clock components use the same fixed UTC+8 standard as the existing engines.
/// Existing stored epochs are never migrated or rewritten by this adapter.
enum BirthClockInput {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
