import Foundation

enum RelativeTime {
    static func string(from date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 60 {
            return "just now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) \(hours == 1 ? "hour" : "hours") ago"
        }

        let days = hours / 24
        return "\(days) \(days == 1 ? "day" : "days") ago"
    }
}
