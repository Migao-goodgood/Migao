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

enum DietUploadState: Equatable {
    case idle
    case loading
    case review(DietPhotoAnalysisDraft)
    case failed(String)

    var isBusy: Bool {
        if case .loading = self { return true }
        return false
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
        let text = normalizedCaloriesText
        guard !text.isEmpty,
              text.range(of: #"^\d{1,5}(?:\.\d)?$"#, options: .regularExpression) != nil,
              let value = Double(text),
              value.isFinite,
              (0...20_000).contains(value) else { return nil }
        return value
    }

    var caloriesInputIsValid: Bool {
        normalizedCaloriesText.isEmpty || caloriesKcal != nil
    }

    var canSave: Bool {
        caloriesInputIsValid
            && (hasPreservedContent || !trimmedTitle.isEmpty || caloriesKcal != nil)
    }

    private var normalizedCaloriesText: String {
        caloriesText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
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
