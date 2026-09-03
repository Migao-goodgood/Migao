import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(Vision)
import Vision
#endif

/// Device-side Vision adapter. It never uploads the report image.
enum InBodyOCRService {
    static func recognize(data: Data) -> InBodyReportAnalysis {
        #if canImport(Vision) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3_000
                ] as CFDictionary
              ) else {
            return emptyResult
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return emptyResult
        }

        let orderedResults = request.results?.sorted { lhs, rhs in
            let verticalDelta = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(verticalDelta) > 0.01 { return verticalDelta > 0 }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let lines = orderedResults?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
        return parseRecognizedLines(lines)
        #else
        return emptyResult
        #endif
    }

    private static var emptyResult: InBodyReportAnalysis {
        InBodyReportAnalysis(
            weightKg: nil,
            bodyFatPercent: nil,
            skeletalMuscleKg: nil,
            visceralFatLevel: nil,
            bmi: nil,
            score: nil,
            recognizedText: "",
            matchedFieldCount: 0,
            provider: .localOCR,
            confidence: 0,
            parserVersion: "vision-2"
        )
    }

    /// Converts Vision's ordered text lines into a reviewable draft. Kept
    /// internal so focused parser tests do not need to invoke Vision itself.
    static func parseRecognizedLines(_ lines: [String]) -> InBodyReportAnalysis {
        let text = lines.joined(separator: "\n")
        var matched = 0

        let measurementDate = firstDate(after: ["测试日期", "测量日期", "测试时间", "测量时间"], in: lines)
        let height = firstNumber(after: ["身高"], in: lines, range: 80...250)
        let age = firstNumber(after: ["年龄"], in: lines, range: 5...120).map(Int.init)
        let sex = firstText(after: ["性别"], candidates: ["女性", "女", "男性", "男"], in: lines)
        let deviceModel = firstDeviceModel(in: lines)

        let weight = firstNumber(
            after: ["体重"],
            excluding: ["目标体重", "标准体重", "体重控制"],
            in: lines,
            range: 20...300
        )
        matched += weight == nil ? 0 : 1

        let bodyFatKg = firstNumber(
            after: ["体脂肪量", "体脂肪质量", "体脂肪"],
            excluding: ["体脂肪百分比", "体脂肪率", "体脂百分比"],
            in: lines,
            range: 0.5...200
        )

        let bodyFat = firstNumber(after: ["体脂肪百分比", "体脂肪率", "体脂百分比"], in: lines, range: 1...80)
        matched += bodyFat == nil ? 0 : 1

        let muscle = firstNumber(after: ["骨骼肌"], excluding: ["骨骼肌控制"], in: lines, range: 1...150)
        matched += muscle == nil ? 0 : 1

        let visceral = firstNumber(after: ["内脏脂肪等级"], in: lines, range: 0...50)
        matched += visceral == nil ? 0 : 1

        let bmi = firstNumber(after: ["BMI"], in: lines, range: 5...80)
        matched += bmi == nil ? 0 : 1

        let score = firstNumber(after: ["InBody 评分", "InBody评分"], in: lines, range: 0...100).map(Int.init)
        matched += score == nil ? 0 : 1

        let waistHipRatio = firstNumber(after: ["腰臀比"], in: lines, range: 0.4...1.8)
        let totalBodyWater = firstNumber(after: ["身体总水分", "总体水分", "总水分"], in: lines, range: 5...100)
        let protein = firstNumber(after: ["蛋白质"], in: lines, range: 1...40)
        let mineral = firstNumber(after: ["无机盐", "矿物质"], in: lines, range: 0.5...15)
        let fatFreeMass = firstNumber(after: ["去脂体重", "去脂体质量"], in: lines, range: 10...250)
        let bodyCellMass = firstNumber(after: ["身体细胞量", "体细胞量"], in: lines, range: 5...150)
        let basalMetabolicRate = firstNumber(after: ["基础代谢率", "基础代谢"], in: lines, range: 500...5_000)
        let smi = firstNumber(after: ["SMI"], in: lines, range: 1...20)

        return InBodyReportAnalysis(
            measurementDate: measurementDate,
            heightCm: height,
            age: age,
            sex: sex,
            deviceModel: deviceModel,
            weightKg: weight,
            bodyFatKg: bodyFatKg,
            bodyFatPercent: bodyFat,
            skeletalMuscleKg: muscle,
            visceralFatLevel: visceral,
            bmi: bmi,
            score: score,
            waistHipRatio: waistHipRatio,
            totalBodyWaterL: totalBodyWater,
            proteinKg: protein,
            mineralKg: mineral,
            fatFreeMassKg: fatFreeMass,
            bodyCellMassKg: bodyCellMass,
            basalMetabolicRate: basalMetabolicRate,
            smiKgPerM2: smi,
            recognizedText: text,
            matchedFieldCount: matched,
            provider: .localOCR,
            confidence: Double(matched) / 6,
            parserVersion: "vision-2"
        )
    }

    private static func firstNumber(
        after labels: [String],
        excluding excludedLabels: [String] = [],
        in lines: [String],
        range: ClosedRange<Double>
    ) -> Double? {
        for (index, line) in lines.enumerated() {
            guard !excludedLabels.contains(where: { line.localizedCaseInsensitiveContains($0) }),
                  let labelRange = labels
                    .sorted(by: { $0.count > $1.count })
                    .compactMap({ line.range(of: $0, options: [.caseInsensitive]) })
                    .first else { continue }

            let suffix = String(line[labelRange.upperBound...])
            for value in numbers(in: suffix) where range.contains(value) {
                return value
            }

            guard index + 1 < lines.count else { continue }
            let following = lines[(index + 1)...min(lines.count - 1, index + 2)].joined(separator: " ")
            for value in numbers(in: following) where range.contains(value) { return value }
        }
        return nil
    }

    private static func firstDate(after labels: [String], in lines: [String]) -> Date? {
        for (index, line) in lines.enumerated() {
            guard labels.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            let context = lines[index...min(lines.count - 1, index + 2)].joined(separator: " ")
            if let date = date(in: context) { return date }
        }
        return date(in: lines.joined(separator: " "))
    }

    private static func date(in text: String) -> Date? {
        let pattern = #"(20\d{2})\s*[./年-]\s*(\d{1,2})\s*[./月-]\s*(\d{1,2})(?:\s*日)?(?:\s*[,，]?\s*(\d{1,2})\s*[:：]\s*(\d{1,2}))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }

        func integer(at index: Int) -> Int? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }

        guard let year = integer(at: 1), let month = integer(at: 2), let day = integer(at: 3) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = integer(at: 4) ?? 12
        components.minute = integer(at: 5) ?? 0
        guard let value = components.date,
              value >= earliestMeasurementDate,
              value <= Date().addingTimeInterval(5 * 60) else {
            return nil
        }
        return value
    }

    private static var earliestMeasurementDate: Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
    }

    private static func firstText(after labels: [String], candidates: [String], in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard labels.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            let context = lines[index...min(lines.count - 1, index + 1)].joined(separator: " ")
            if let match = candidates.first(where: { context.localizedCaseInsensitiveContains($0) }) {
                return match
            }
        }
        return nil
    }

    private static func firstDeviceModel(in lines: [String]) -> String? {
        let text = lines.joined(separator: " ")
        let pattern = #"InBody\s*[-_]?\s*([A-Za-z]?\d{2,4}[A-Za-z]?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: " ", with: "")
    }

    private static func numbers(in line: String) -> [Double] {
        let pattern = #"\d{1,5}(?:[.,]\d{1,2})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.matches(in: line, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: line) else { return nil }
            return Double(line[matchRange].replacingOccurrences(of: ",", with: "."))
        }
    }
}

/// Type alias retained for source compatibility with older preview/test code.
typealias InBodyOCRResult = InBodyReportAnalysis

struct LocalInBodyReportAnalyzer: InBodyReportAnalyzing {
    func analyze(data: Data) async -> InBodyReportAnalysis {
        var result = InBodyOCRService.recognize(data: data)
        result.message = result.recognizedFieldCount > 0
            ? "设备端已识别 \(result.recognizedFieldCount) 项，请核对结果"
            : "未识别到报告字段，请在核对页填写或重新上传清晰照片"
        return result
    }
}
