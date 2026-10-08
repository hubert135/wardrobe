import Foundation
import OutfitEngine
import SwiftData

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    /// Stable Sign in with Apple user identifier, once signed in.
    var appleUserID: String?
    var cityOverride: String?
    var preferredStylesRaw: [String] = [Style.smartCasual.rawValue]
    var favoriteColors: [String] = []
    var avoidedColors: [String] = []
    var favoriteBrands: [String] = []
    var defaultBudget: Double?
    var currencyCode: String = "EUR"
    var notificationsEnabled: Bool = false
    var notificationHour: Int = 7
    var notificationMinute: Int = 30
    var appearanceRaw: String = AppearancePreference.system.rawValue
    var lastWeekdayOccasionRaw: String?
    var lastWeekendOccasionRaw: String?
    var lastStyleRaw: String?
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date()

    init() {
        currencyCode = Locale.current.currency?.identifier ?? "EUR"
    }

    var preferredStyles: [Style] {
        get { preferredStylesRaw.compactMap(Style.init(rawValue:)) }
        set { preferredStylesRaw = newValue.map(\.rawValue) }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var stylePreferences: StylePreferences {
        StylePreferences(preferredStyles: preferredStyles, favoriteColors: Set(favoriteColors), avoidedColors: Set(avoidedColors))
    }

    var notificationTime: DateComponents {
        DateComponents(hour: notificationHour, minute: notificationMinute)
    }

    /// Last chosen occasion for this kind of day, or the default ("work" on weekdays, "weekend" otherwise).
    func occasion(for date: Date, calendar: Calendar = .current) -> Occasion {
        let raw = calendar.isDateInWeekend(date) ? lastWeekendOccasionRaw : lastWeekdayOccasionRaw
        return raw.flatMap(Occasion.init(rawValue:)) ?? Occasion.defaultFor(date: date, calendar: calendar)
    }

    func remember(occasion: Occasion, style: Style, on date: Date, calendar: Calendar = .current) {
        if calendar.isDateInWeekend(date) {
            lastWeekendOccasionRaw = occasion.rawValue
        } else {
            lastWeekdayOccasionRaw = occasion.rawValue
        }
        lastStyleRaw = style.rawValue
    }

    var lastStyle: Style {
        lastStyleRaw.flatMap(Style.init(rawValue:)) ?? preferredStyles.first ?? .smartCasual
    }
}
