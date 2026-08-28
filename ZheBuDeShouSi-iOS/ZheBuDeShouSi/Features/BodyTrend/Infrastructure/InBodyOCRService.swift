import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(Vision)
import Vision
#endif

struct InBodyOCRResult: Equatable {
    var weightKg: Double?
    var bodyFatPercent: Double?
    var skeletalMuscleKg: Double?
    var visceralFatLevel: Double?
    var bmi: Double?
    var score: Int?
    var recognizedText: String
    var matchedFieldCount: Int
}

enum InBodyOCRService {
    static func recognize(data: Data) -> InBodyOCRResult {
        #if canImport(Vision) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return emptyResult
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return emptyResult
        }

        let lines = request.results?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
        return parse(lines: lines)
        #else
        return emptyResult
        #endif
    }

    private static var emptyResult: InBodyOCRResult {
        InBodyOCRResult(
            weightKg: nil,
            bodyFatPercent: nil,
            skeletalMuscleKg: nil,
            visceralFatLevel: nil,
            bmi: nil,
            score: nil,
            recognizedText: "",
            matchedFieldCount: 0
        )
    }

    private static func parse(lines: [String]) -> InBodyOCRResult {
        let text = lines.joined(separator: "\n")
        var matched = 0

        let weight = firstNumber(after: ["体重"], in: lines, range: 20...300)
        matched += weight == nil ? 0 : 1

        let bodyFat = firstNumber(after: ["体脂肪百分比", "体脂肪率", "体脂百分比"], in: lines, range: 1...80)
        matched += bodyFat == nil ? 0 : 1

        let muscle = firstNumber(after: ["骨骼肌"], in: lines, range: 1...150)
        matched += muscle == nil ? 0 : 1

        let visceral = firstNumber(after: ["内脏脂肪等级"], in: lines, range: 0...50)
        matched += visceral == nil ? 0 : 1

        let bmi = firstNumber(after: ["BMI"], in: lines, range: 5...80)
        matched += bmi == nil ? 0 : 1

        let score = firstNumber(after: ["InBody 评分", "InBody评分"], in: lines, range: 0...100).map(Int.init)
        matched += score == nil ? 0 : 1

        return InBodyOCRResult(
            weightKg: weight,
            bodyFatPercent: bodyFat,
            skeletalMuscleKg: muscle,
            visceralFatLevel: visceral,
            bmi: bmi,
            score: score,
            recognizedText: text,
            matchedFieldCount: matched
        )
    }

    private static func firstNumber(after labels: [String], in lines: [String], range: ClosedRange<Double>) -> Double? {
        for (index, line) in lines.enumerated() {
            guard labels.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            let context = lines[index...min(lines.count - 1, index + 2)].joined(separator: " ")
            for value in numbers(in: context) where range.contains(value) {
                return value
            }
        }
        return nil
    }

    private static func numbers(in line: String) -> [Double] {
        let pattern = #"\d{1,3}(?:[.,]\d{1,2})?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.matches(in: line, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: line) else { return nil }
            return Double(line[matchRange].replacingOccurrences(of: ",", with: "."))
        }
    }
}
