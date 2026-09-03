import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(Vision)
import Vision
#endif

/// A conservative, on-device first pass for meal photos.
///
/// This service only extracts text that is visibly present in a photo (for
/// example a menu label or a printed kcal value). It never invents a food or
/// calorie estimate. A future GPT/vision backend can implement the same
/// `DietPhotoAnalysisHandler` contract without changing the UI or store.
enum DietPhotoAnalysisService {
    static func analyze(request: DietPhotoAnalysisRequest) async -> DietPhotoAnalysisDraft? {
        #if canImport(Vision) && canImport(ImageIO)
        let lines = request.imageData.flatMap(recognizeText)
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let calories = calorieValue(in: cleanedLines)
        let title = mealTitle(in: cleanedLines)
        let foods = foodItems(in: cleanedLines, title: title)
        let hasSignal = calories != nil || !title.isEmpty || !foods.isEmpty

        return DietPhotoAnalysisDraft(
            mealType: mealType(for: request.date),
            title: title,
            caloriesKcal: calories,
            foods: foods,
            confidence: hasSignal ? min(0.82, 0.35 + Double(cleanedLines.count) * 0.06) : nil,
            sourceLabel: hasSignal
                ? "设备端文字识别 · 请核对名称和热量"
                : "照片已载入 · 未读到明确文字，请手动确认"
        )
        #else
        return DietPhotoAnalysisDraft(
            mealType: mealType(for: request.date),
            sourceLabel: "照片已载入 · 请手动确认名称和热量"
        )
        #endif
    }

    #if canImport(Vision) && canImport(ImageIO)
    private static func recognizeText(in data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 2_000
                  ] as CFDictionary
              ) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US", "ja-JP"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }

    private static func calorieValue(in lines: [String]) -> Int? {
        let text = lines.joined(separator: " ")
        let pattern = #"(?i)(\d{2,4}(?:[.,]\d{1,1})?)\s*(?:kcal|千卡|大卡)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range].replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (0...20_000).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private static func mealTitle(in lines: [String]) -> String {
        let ignored = ["kcal", "千卡", "大卡", "热量", "营养成分", "成分表", "nutrition", "calories"]
        return lines.first { line in
            let lower = line.lowercased()
            guard !ignored.contains(where: { lower.contains($0) }) else { return false }
            guard line.rangeOfCharacter(from: .letters) != nil || line.rangeOfCharacter(from: .decimalDigits) != nil else {
                return false
            }
            return line.count >= 2 && line.count <= 28
        }.map { String($0.prefix(80)) } ?? ""
    }

    private static func foodItems(in lines: [String], title: String) -> [RecognizedFoodItem] {
        let ignored = Set([title, "kcal", "千卡", "大卡", "热量", "营养成分", "成分表"])
        return lines
            .filter { line in
                let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized != title
                    && !ignored.contains(normalized)
                    && normalized.count >= 2
                    && normalized.count <= 22
                    && normalized.range(of: #"^\d+[.,]?\d*$"#, options: .regularExpression) == nil
            }
            .prefix(4)
            .map { RecognizedFoodItem(name: String($0.prefix(80))) }
    }
    #endif

    private static func mealType(for date: Date) -> DietMealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}
