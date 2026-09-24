import Foundation
import SwiftUI

/// The two ways of scanning a month: a compact calendar and an image-first food map.
enum DietDisplayMode: String, CaseIterable, Identifiable {
    case calendar = "日历"
    case mosaic = "图谱"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .mosaic: return "square.grid.2x2"
        }
    }
}

/// Text input retains an empty value as unknown rather than manufacturing a
/// zero-calorie meal. Both the capture and edit forms use the same bounds.
enum DietEntryInputRules {
    static func normalizedCalories(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }

    static func calories(_ text: String, wholeNumbersOnly: Bool = false) -> Double? {
        let normalized = normalizedCalories(text)
        let pattern = wholeNumbersOnly ? #"^\d{1,5}$"# : #"^\d{1,5}(?:\.\d)?$"#
        guard !normalized.isEmpty,
              normalized.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite,
              (0...20_000).contains(value) else { return nil }
        return value
    }

    static var supportedDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return firstDay...tomorrow.addingTimeInterval(-0.001)
    }
}

/// Editable presentation values for an existing meal. Persistence remains in
/// DietStore so the UI cannot accidentally create a replacement record.
struct DietMealEditDraft: Equatable {
    let mealID: UUID
    let hasPreservedContent: Bool
    var mealType: DietMealType
    var title: String
    var recordedAt: Date
    var caloriesText: String

    init(meal: MealRecord) {
        mealID = meal.id
        hasPreservedContent = !meal.images.isEmpty || !meal.foods.isEmpty
        mealType = meal.mealType
        title = meal.title
        recordedAt = meal.date
        if let calories = meal.calculatedCaloriesKcal {
            let rounded = (calories * 10).rounded() / 10
            caloriesText = rounded.rounded() == rounded
                ? String(format: "%.0f", rounded)
                : String(format: "%.1f", rounded)
        } else {
            caloriesText = ""
        }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var caloriesKcal: Double? {
        DietEntryInputRules.calories(caloriesText)
    }

    var caloriesInputIsValid: Bool {
        normalizedCaloriesText.isEmpty || caloriesKcal != nil
    }

    var canSave: Bool {
        caloriesInputIsValid
            && DietEntryInputRules.supportedDateRange.contains(recordedAt)
            && (hasPreservedContent || !trimmedTitle.isEmpty || caloriesKcal != nil)
    }

    private var normalizedCaloriesText: String {
        DietEntryInputRules.normalizedCalories(caloriesText)
    }
}

enum DietPalette {
    static let paper = Color(hex: "FFF8FC")
    static let surface = Color.white.opacity(0.96)
    static let ink = Color(hex: "3B2E3D")
    static let muted = Color(hex: "9B879B")
    static let rule = Color(hex: "EEDDE8")
    static let pink = Color(hex: "ED7FA8")
    static let pinkDeep = Color(hex: "C85C88")
    static let pinkWash = Color(hex: "FDE8F0")
    static let lilac = Color(hex: "A68FCE")
    static let lilacWash = Color(hex: "F1ECFA")
    static let peach = Color(hex: "F2AF8D")
    static let mint = Color(hex: "77BDAA")
    static let mintWash = Color(hex: "EAF7F2")
    static let gold = Color(hex: "C8A35E")
}

extension View {
    /// Diet-only surface styling. Keeping this local avoids coupling the shared
    /// weight cards to the more editorial food-journal treatment.
    func dietSurface(radius: CGFloat = 22) -> some View {
        self
            .background(DietPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DietPalette.rule, lineWidth: 1)
            }
            .shadow(color: DietPalette.pink.opacity(0.10), radius: 18, y: 8)
    }
}
