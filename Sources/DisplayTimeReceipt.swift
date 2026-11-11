import Foundation

/// Fixed display receipt matching the existing chart engines' Beijing clock.
/// Does not convert stored epochs or change any calculation input.
enum DisplayTimeReceipt {
    static func beijing(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date) + "（北京时间 UTC+8）"
    }
}
