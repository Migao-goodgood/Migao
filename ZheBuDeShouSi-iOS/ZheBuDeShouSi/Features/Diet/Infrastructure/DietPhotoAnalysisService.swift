import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(Vision)
import Vision
#endif

/// 免费、纯本地的餐食照片文字识别。
/// Vision 只读取照片上已经印出的文字和明确的 kcal 数字；普通饭菜照片
/// 不会被臆测成某种食物或热量。这里不包含网络请求、远程模型或 API 密钥。
enum DietPhotoAnalysisService {
    static func analyze(request: DietPhotoAnalysisRequest) async -> DietPhotoAnalysisDraft? {
        #if canImport(Vision) && canImport(ImageIO)
        return draft(fromRecognizedLines: request.imageData.flatMap(recognizeText), date: request.date)
        #else
        return DietPhotoAnalysisDraft(mealType: mealType(for: request.date), sourceLabel: "照片已载入 · 当前设备不支持本地文字识别，请手动确认热量")
        #endif
    }

    /// Pure parser kept separate from Vision so ambiguous labels can be tested
    /// without a camera, OCR runtime, network, or paid service.
    static func draft(fromRecognizedLines lines: [String], date: Date) -> DietPhotoAnalysisDraft {
        let cleanedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let parsed = parseCalories(from: cleanedLines)
        let label: String
        if let calories = parsed.calories {
            label = "设备端文字识别 · 读到 \(calories) kcal。请核对单位、每份或每100g，以及实际食用量。"
        } else if let reason = parsed.reason {
            label = "设备端文字识别 · \(reason)，请手动确认"
        } else {
            label = cleanedLines.isEmpty ? "照片已载入 · 未读到明确热量，请手动确认" : "设备端文字识别 · 未读到明确热量，请手动确认"
        }
        return DietPhotoAnalysisDraft(mealType: mealType(for: date), title: "", caloriesKcal: parsed.calories,
            foods: [], confidence: parsed.calories == nil ? nil : 0.7, sourceLabel: label)
    }

    private struct CalorieParseResult { var calories: Int?; var reason: String? }

    /// Accept one unique kcal value. Per-100 g/ml references, kJ-only values,
    /// negatives and out-of-range numbers remain unknown rather than guessing.
    private static func parseCalories(from lines: [String]) -> CalorieParseResult {
        // Vision often splits a nutrition table's basis and energy into
        // separate lines. Without layout/serving information a per-100 label
        // anywhere in the recognized photo makes a meal total ambiguous.
        if isReferenceValue(lines.joined(separator: " ")) {
            return CalorieParseResult(reason: "检测到每 100 克/毫升参考值")
        }
        let pattern = #"(?i)([-−+]?\s*\d+(?:[.,]\d+)?)\s*(?:kcal|千卡|大卡)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return CalorieParseResult(reason: "热量格式无法核对") }
        var values: [Double] = []
        var sawInvalid = false, sawKJ = false
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = expression.matches(in: line, range: range)
            if matches.isEmpty && (line.lowercased().contains("kj") || line.contains("千焦")) { sawKJ = true }
            for match in matches {
                guard let numberRange = Range(match.range(at: 1), in: line) else { sawInvalid = true; continue }
                let raw = line[numberRange].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: ".")
                guard let value = Double(raw), value.isFinite else { sawInvalid = true; continue }
                guard value >= 0, value <= 20_000 else { sawInvalid = true; continue }
                // Compare original values first: 100.1 and 100.2 are distinct
                // readings even though both would display as 100 kcal.
                if !values.contains(value) { values.append(value) }
            }
        }
        if sawInvalid { return CalorieParseResult(reason: "热量数值超出可确认范围") }
        if values.count > 1 { return CalorieParseResult(reason: "检测到多个不同热量值") }
        if let value = values.first { return CalorieParseResult(calories: Int(value.rounded())) }
        if sawKJ { return CalorieParseResult(reason: "照片只显示 kJ/千焦，未自动换算为本餐 kcal") }
        return CalorieParseResult()
    }

    private static func isReferenceValue(_ context: String) -> Bool {
        let compact = context.lowercased().filter { !$0.isWhitespace }
        return compact.contains("100g") || compact.contains("100克")
            || compact.contains("100ml") || compact.contains("100毫升")
            || compact.contains("每100") || compact.contains("/100")
    }

    #if canImport(Vision) && canImport(ImageIO)
    private static func recognizeText(in data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2_000] as CFDictionary) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US", "ja-JP"]
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }
    #endif

    private static func mealType(for date: Date) -> DietMealType {
        switch Calendar.current.component(.hour, from: date) { case 5..<11: return .breakfast; case 11..<16: return .lunch; case 16..<22: return .dinner; default: return .snack }
    }
}
