import Foundation
import SwiftUI

// Only the design-token initializer is stubbed: these tests exercise input
// models, never render views or read an application's live persistence.
extension Color {
    init(hex: String) { self = .clear }
}

@main
struct DietInputValidationTests {
    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("empty kcal stays unknown", emptyCalories),
            ("real zero remains a valid value", explicitZero),
            ("capture rejects malformed or out-of-range kcal", invalidCaptureCalories),
            ("meal edits retain one-decimal precision", decimalEditCalories),
            ("photo-only edit is saveable and retains identity", photoOnlyEdit),
            ("invalid edit cannot save despite having a photo", invalidEdit),
            ("date bounds reject future and pre-2000 records", dateBounds),
            ("a record still requires some content", contentRequirement)
        ]
        for (name, test) in cases {
            try test()
            print("PASS: \(name)")
        }
        print("All \(cases.count) diet input validation tests passed.")
    }

    private static func emptyCalories() throws {
        for value in ["", " ", "\n\t"] {
            try require(DietEntryInputRules.calories(value) == nil, "Blank kcal became a number")
            try require(DietEntryInputRules.calories(value, wholeNumbersOnly: true) == nil, "Blank capture kcal became a number")
        }
    }

    private static func explicitZero() throws {
        try require(DietEntryInputRules.calories("0", wholeNumbersOnly: true) == 0, "Explicit zero rejected")
        var edit = photoEdit()
        edit.caloriesText = "0"
        try require(edit.canSave && edit.caloriesKcal == 0, "An explicit zero cannot be saved")
        edit.caloriesText = ""
        try require(edit.canSave && edit.caloriesKcal == nil, "Clearing zero must restore unknown")
    }

    private static func invalidCaptureCalories() throws {
        for value in ["-1", "20001", "12x", "NaN", "Infinity", "1.5", "1e3"] {
            try require(DietEntryInputRules.calories(value, wholeNumbersOnly: true) == nil, "Invalid capture kcal accepted: \(value)")
        }
        try require(DietEntryInputRules.calories("20000", wholeNumbersOnly: true) == 20_000, "Upper kcal boundary rejected")
    }

    private static func decimalEditCalories() throws {
        var edit = photoEdit()
        edit.caloriesText = "420,5"
        try require(edit.canSave && edit.caloriesKcal == 420.5, "Single-decimal input lost precision")
        edit.caloriesText = "420.55"
        try require(!edit.canSave, "More than one decimal should require correction")
    }

    private static func photoOnlyEdit() throws {
        let record = photoRecord()
        let edit = DietMealEditDraft(meal: record)
        try require(edit.canSave, "A photo-only meal cannot be saved")
        try require(edit.trimmedTitle.isEmpty && edit.caloriesKcal == nil, "Missing fields were invented")
        try require(edit.mealID == record.id, "Edit changed the record identity")
    }

    private static func invalidEdit() throws {
        var edit = photoEdit()
        edit.caloriesText = "800"
        try require(edit.caloriesKcal == 800, "Valid baseline missing")
        edit.caloriesText = "800x"
        try require(!edit.canSave && edit.caloriesKcal == nil, "Invalid input retained a stale numeric value")
    }

    private static func dateBounds() throws {
        var edit = photoEdit()
        let range = DietEntryInputRules.supportedDateRange
        edit.recordedAt = range.lowerBound
        try require(edit.canSave, "First supported date rejected")
        edit.recordedAt = range.lowerBound.addingTimeInterval(-1)
        try require(!edit.canSave, "Pre-2000 date accepted")
        edit.recordedAt = Date().addingTimeInterval(7 * 86_400)
        try require(!edit.canSave, "Future record accepted")
        edit.recordedAt = .now
        try require(edit.canSave, "Today's date rejected")
    }

    private static func contentRequirement() throws {
        var empty = DietMealEditDraft(meal: MealRecord())
        try require(!empty.canSave, "Completely empty record accepted")
        empty.title = "午餐"
        try require(empty.canSave, "Title-only legacy record cannot be edited")
    }

    private static func photoRecord() -> MealRecord {
        MealRecord(images: [MealImageMetadata(data: Data([1, 2, 3]))], source: .photo)
    }

    private static func photoEdit() -> DietMealEditDraft { DietMealEditDraft(meal: photoRecord()) }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
