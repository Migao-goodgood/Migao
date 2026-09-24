import Foundation
import AppKit
import Vision

@main
struct DietLocalOCRTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func draft(_ lines: [String]) -> DietPhotoAnalysisDraft {
        DietPhotoAnalysisService.draft(fromRecognizedLines: lines, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @MainActor
    static func main() async {
        let same = draft(["热量 480 kcal", "Calories 480 kcal"])
        require(same.caloriesKcal == 480, "Repeated same kcal values must be de-duplicated")
        require(same.title.isEmpty && same.foods.isEmpty, "Local OCR must not invent a meal name or food list")

        let decimal = draft(["每份 123.6 千卡"])
        require(decimal.caloriesKcal == 124, "Decimal kcal must round to an integer")
        let repeatedDecimal = draft(["100.10 kcal", "100.1 千卡"])
        require(repeatedDecimal.caloriesKcal == 100, "Numerically identical decimals remain one reading")
        let distinctDecimals = draft(["100.1 kcal", "100.2 千卡"])
        require(distinctDecimals.caloriesKcal == nil && distinctDecimals.sourceLabel.contains("多个不同"), "Distinct decimals cannot be merged by rounding")

        let zero = draft(["能量 0 大卡"])
        require(zero.caloriesKcal == 0, "Explicit zero kcal is a valid known value")

        for lines in [
            ["早餐 420 kcal", "午餐 680 kcal"],
            ["能量 -20 kcal"],
            ["能量 20001 kcal"],
            ["每100g 220 kcal"],
            ["每 100 毫升 35 千卡"],
            ["每100g", "能量", "220 kcal"],
            ["per 100 ml", "Energy", "35 kcal"],
            ["每", "100", "毫升", "35 千卡"],
            ["能量 120 kJ"],
            ["蛋白质 12 g，脂肪 8 g"]
        ] {
            let result = draft(lines)
            require(result.caloriesKcal == nil, "Ambiguous kcal must remain unknown: \(lines)")
            require(result.title.isEmpty && result.foods.isEmpty, "Ambiguous OCR must not create labels")
            require(result.sourceLabel.contains("请手动确认"), "Ambiguous OCR must ask the user to confirm")
        }

        let chinese = draft(["本餐热量：356千卡"])
        require(chinese.caloriesKcal == 356, "Chinese 千卡 labels must be recognized")
        let noText = draft([])
        require(noText.caloriesKcal == nil && noText.sourceLabel.contains("手动确认"), "No text still produces a saveable unknown draft")

        let invalidImage = await DietPhotoAnalysisService.analyze(request: DietPhotoAnalysisRequest(date: Date(), imageData: [Data([1, 2, 3])]))
        require(invalidImage?.caloriesKcal == nil, "Invalid photo never receives a guessed kcal")
        print("PASS: local diet OCR parser — duplicate, distinct decimal, cross-line reference, zero, range, unit and unknown cases")

        // Exercise actual Vision with deterministic in-memory images, not a
        // mocked parser result. Neither fixture contains user data.
        let readableData = fixture(text: "Energy 320 kcal", format: .png)
        let readable = await DietPhotoAnalysisService.analyze(request: DietPhotoAnalysisRequest(
            date: Date(), imageData: [readableData]))
        if readable?.caloriesKcal != 320 {
            let diagnostic = VNRecognizeTextRequest()
            diagnostic.recognitionLevel = .accurate
            diagnostic.recognitionLanguages = ["zh-Hans", "en-US", "ja-JP"]
            do {
                try VNImageRequestHandler(data: readableData, options: [:]).perform([diagnostic])
                let lines = diagnostic.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                FileHandle.standardError.write(Data("Real Vision diagnostic lines: \(lines); service: \(String(describing: readable?.sourceLabel))\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("Real Vision failed in current environment: \(error)\n".utf8))
            }
        }
        require(readable?.caloriesKcal == 320, "Real Vision did not read the visible Energy 320 kcal fixture")
        require(readable?.title.isEmpty == true && readable?.foods.isEmpty == true, "Real Vision must not invent food labels")
        print("PASS: real on-device Vision reads Energy 320 kcal from an in-memory PNG")
        let blank = await DietPhotoAnalysisService.analyze(request: DietPhotoAnalysisRequest(
            date: Date(), imageData: [fixture(text: nil, format: .jpeg)]))
        require(blank != nil && blank?.caloriesKcal == nil, "Real Vision must keep a blank JPEG unknown")
        print("PASS: real on-device Vision leaves an in-memory blank JPEG unknown; no network path")
    }

    @MainActor
    static func fixture(text: String?, format: NSBitmapImageRep.FileType) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1_200, pixelsHigh: 360,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1_200, height: 360).fill()
        if let text {
            (text as NSString).draw(at: NSPoint(x: 80, y: 140), withAttributes: [
                .font: NSFont.systemFont(ofSize: 76, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: format, properties: [.compressionFactor: 0.95])!
    }
}
