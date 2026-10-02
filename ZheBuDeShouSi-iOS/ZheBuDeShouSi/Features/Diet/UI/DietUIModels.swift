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
    static let paper = Color(hex: "F7F7F9")
    static let surface = Color.white.opacity(0.98)
    static let ink = Color(hex: "1D1D1F")
    static let muted = Color(hex: "8E8E93")
    static let rule = Color(hex: "E5E5EA")
    static let pink = Color(hex: "4E9B82")
    static let pinkDeep = Color(hex: "3F8D77")
    static let pinkWash = Color(hex: "E7F3EF")
    static let lilac = Color(hex: "4F8FAF")
    static let lilacWash = Color(hex: "E7F1F6")
    static let peach = Color(hex: "D89A72")
    static let mint = Color(hex: "4E9B82")
    static let mintWash = Color(hex: "E7F3EF")
    static let gold = Color(hex: "B19156")

    // Semantic aliases keep the feature vocabulary clear while legacy names
    // remain source-compatible with existing meal views.
    static let primary = pinkDeep
    static let secondary = lilac
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
            .shadow(color: Color.black.opacity(0.045), radius: 13, y: 5)
    }
}
