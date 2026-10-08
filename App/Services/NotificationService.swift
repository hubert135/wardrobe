import Foundation
import UserNotifications

/// Optional daily morning reminder ("Your outfits for today are ready").
final class NotificationService {
    static let morningIdentifier = "wardrobe.morning"
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func scheduleMorningReminder(hour: Int, minute: Int) async -> Bool {
        guard await requestAuthorization() else { return false }
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Your outfits for today are ready."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        let request = UNNotificationRequest(identifier: Self.morningIdentifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelMorningReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningIdentifier])
    }
}
