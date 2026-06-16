import Foundation

// Parses the various created_at shapes (ISO with/without fractional seconds or
// timezone) and formats iMessage-style separator labels.
enum ChatDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let noTimezone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    static func parse(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s) ?? noTimezone.date(from: s)
    }

    static func separatorLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)   // "2:34 PM"
        if cal.isDateInToday(date) { return time }
        if cal.isDateInYesterday(date) { return "Yesterday  \(time)" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.wide)))  \(time)"
        }
        return "\(date.formatted(.dateTime.month().day()))  \(time)"
    }
}

extension MessageRecord {
    var date: Date? { ChatDate.parse(created_at) }
}
