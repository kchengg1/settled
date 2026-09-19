import Foundation
import UserNotifications

/// Local notifications only — there is no server to send anything.
enum Reminders {

    /// Schedules a one-shot reminder. Returns false if the user declined
    /// notification permission.
    static func schedule(id: String, title: String, body: String, at date: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        return true
    }

    static func morning(daysFromNow days: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
