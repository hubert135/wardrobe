import Foundation

/// Outfit positions. Every outfit has at most one garment per slot.
public enum Slot: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case outerwear, top, bottom, shoes, accessory

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .outerwear: "Outerwear"
        case .top: "Top"
        case .bottom: "Bottom"
        case .shoes: "Shoes"
        case .accessory: "Accessory"
        }
    }

    /// Slots that every complete outfit must fill.
    public static let required: [Slot] = [.top, .bottom, .shoes]

    private var sortIndex: Int { Slot.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Slot, rhs: Slot) -> Bool { lhs.sortIndex < rhs.sortIndex }
}

public enum GarmentCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case shirt
    case tShirt = "t-shirt"
    case polo, sweater, hoodie, blazer, jacket, coat, trousers, jeans, chinos, shorts, shoes, accessory, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tShirt: "T-shirt"
        default: rawValue.capitalized
        }
    }

    /// Plural label used in sentences ("4 of your shirts").
    public var pluralName: String {
        switch self {
        case .tShirt: "T-shirts"
        case .trousers, .jeans, .chinos, .shorts, .shoes: rawValue
        case .accessory: "accessories"
        default: rawValue + "s"
        }
    }

    public var slot: Slot? {
        switch self {
        case .shirt, .tShirt, .polo, .sweater, .hoodie: .top
        case .blazer, .jacket, .coat: .outerwear
        case .trousers, .jeans, .chinos, .shorts: .bottom
        case .shoes: .shoes
        case .accessory: .accessory
        case .other: nil
        }
    }

    /// Sensible starting formality when nothing better is known (1 sporty ... 5 formal).
    public var defaultFormality: Int {
        switch self {
        case .hoodie, .shorts: 1
        case .tShirt: 2
        case .polo, .jeans, .jacket, .sweater, .chinos, .shoes, .accessory, .other: 3
        case .shirt, .trousers, .coat, .blazer: 4
        }
    }

    public var isWarmLayer: Bool { self == .sweater || self == .hoodie }

    /// Outerwear that actually protects against cold (a blazer does not count).
    public var isWeatherOuterwear: Bool { self == .jacket || self == .coat }
}

public enum Pattern: String, Codable, CaseIterable, Sendable, Identifiable {
    case solid, striped, checked, patterned

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    /// Subtle patterns can be combined with one other pattern.
    public var isSubtle: Bool { self == .striped }
}

public enum Season: String, Codable, CaseIterable, Sendable, Identifiable {
    case spring, summer, autumn, winter

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    /// Meteorological season for the northern hemisphere.
    public static func from(date: Date, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

public enum Occasion: String, Codable, CaseIterable, Sendable, Identifiable {
    case work
    case businessMeeting = "business_meeting"
    case dinner
    case casualOuting = "casual_outing"
    case weekend, event, travel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .work: "Work"
        case .businessMeeting: "Business meeting"
        case .dinner: "Dinner"
        case .casualOuting: "Casual outing"
        case .weekend: "Weekend"
        case .event: "Event"
        case .travel: "Travel"
        }
    }

    public var formalityRange: ClosedRange<Int> {
        switch self {
        case .work: 2...4
        case .businessMeeting: 4...5
        case .dinner: 3...5
        case .casualOuting: 2...3
        case .weekend: 1...3
        case .event: 4...5
        case .travel: 1...3
        }
    }

    public var allowsShorts: Bool { self == .weekend || self == .casualOuting || self == .travel }

    public static func defaultFor(date: Date, calendar: Calendar = .current) -> Occasion {
        calendar.isDateInWeekend(date) ? .weekend : .work
    }
}

public enum Style: String, Codable, CaseIterable, Sendable, Identifiable {
    case formal
    case smartCasual = "smart_casual"
    case casual, sporty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .formal: "Formal"
        case .smartCasual: "Smart casual"
        case .casual: "Casual"
        case .sporty: "Sporty"
        }
    }

    public var formalityRange: ClosedRange<Int> {
        switch self {
        case .formal: 4...5
        case .smartCasual: 3...4
        case .casual: 2...3
        case .sporty: 1...2
        }
    }
}

public enum Formality {
    public static let range = 1...5

    public static func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }

    public static func label(_ value: Int) -> String {
        switch value {
        case ...1: "Sporty"
        case 2: "Casual"
        case 3: "Smart casual"
        case 4: "Business"
        default: "Formal"
        }
    }

    /// Intersection of two ranges, or `nil` when they do not overlap.
    public static func intersect(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> ClosedRange<Int>? {
        let lower = max(a.lowerBound, b.lowerBound)
        let upper = min(a.upperBound, b.upperBound)
        return lower <= upper ? lower...upper : nil
    }
}
