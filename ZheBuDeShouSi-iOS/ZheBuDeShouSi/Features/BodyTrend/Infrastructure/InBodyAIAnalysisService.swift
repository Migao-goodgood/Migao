import Foundation

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

/// Optional adapter for a product-owned report-analysis backend.
///
/// The backend may call GPT or another vision model, but the client never
/// carries a provider API key. Configure `INBODY_AI_ENDPOINT` as an Info.plist
/// value only when a server endpoint is available. Without it, the pipeline
/// remains fully offline and uses Vision OCR.
struct InBodyAIReportAnalyzer: InBodyReportAnalyzing, Sendable {
    let endpoint: URL?
    let timeout: TimeInterval

    init(endpoint: URL? = Self.bundleEndpoint, timeout: TimeInterval = 30) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    var isConfigured: Bool {
        guard let endpoint else { return false }
        return Self.isAllowed(endpoint)
    }

    func analyze(data: Data) async -> InBodyReportAnalysis {
        guard let endpoint, Self.isAllowed(endpoint) else {
            return fallback(data: data, message: "未配置 AI 服务，已使用设备端识别")
        }

        do {
            let upload = Self.preparedUpload(from: data)
            guard upload.data.count <= 10 * 1024 * 1024 else {
                return fallback(data: data, message: "报告图片过大，已改用设备端识别")
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(
                InBodyAIRequest(
                    imageBase64: upload.data.base64EncodedString(),
                    mimeType: upload.mimeType,
                    schemaVersion: "inbody-2"
                )
            )

            let (payload, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw InBodyAIAnalysisError.badResponse
            }

            let decoder = JSONDecoder()
            let direct = try? decoder.decode(InBodyAIResponse.self, from: payload)
            let envelope = try? decoder.decode(InBodyAIEnvelope.self, from: payload)
            guard let wire = envelope?.analysis ?? envelope?.data ?? envelope?.result ?? direct,
                  wire.hasRecognizedValue else {
                throw InBodyAIAnalysisError.emptyResponse
            }

            // `matchedFieldCount` remains scoped to the original six fields.
            // Some v2 backends report a total including extended fields, so
            // the client always derives this primary count from decoded data.
            let matched = wire.derivedPrimaryMatchedFieldCount
            return InBodyReportAnalysis(
                measurementDate: wire.measurementDate,
                heightCm: wire.heightCm,
                age: wire.age.map { Int($0.rounded()) },
                sex: wire.sex,
                deviceModel: wire.deviceModel,
                weightKg: wire.weightKg,
                bodyFatKg: wire.bodyFatKg,
                bodyFatPercent: wire.bodyFatPercent,
                skeletalMuscleKg: wire.skeletalMuscleKg,
                visceralFatLevel: wire.visceralFatLevel,
                bmi: wire.bmi,
                score: wire.score.map { Int($0.rounded()) },
                waistHipRatio: wire.waistHipRatio,
                totalBodyWaterL: wire.totalBodyWaterL,
                proteinKg: wire.proteinKg,
                mineralKg: wire.mineralKg,
                fatFreeMassKg: wire.fatFreeMassKg,
                bodyCellMassKg: wire.bodyCellMassKg,
                basalMetabolicRate: wire.basalMetabolicRate,
                smiKgPerM2: wire.smiKgPerM2,
                recognizedText: wire.recognizedText ?? "",
                matchedFieldCount: min(6, max(0, matched)),
                provider: .remoteAI,
                confidence: wire.confidence.map { min(1, max(0, $0)) } ?? Double(matched) / 6,
                parserVersion: wire.parserVersion ?? "backend-inbody-2",
                message: wire.message ?? "AI 分析完成，请核对识别结果"
            )
        } catch {
            return fallback(data: data, message: "AI 服务暂不可用，已使用设备端识别")
        }
    }

    private func fallback(data: Data, message: String) -> InBodyReportAnalysis {
        var result = InBodyOCRService.recognize(data: data)
        result.message = result.recognizedFieldCount > 0
            ? message
            : "未识别到报告字段，请在核对页填写或重新上传清晰照片"
        return result
    }

    static var bundleEndpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "INBODY_AI_ENDPOINT") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return url
    }

    private static func isAllowed(_ endpoint: URL) -> Bool {
        guard let scheme = endpoint.scheme?.lowercased() else { return false }
        // Production traffic must be encrypted. Localhost is allowed for a
        // developer-owned proxy during development and never carries a key.
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(endpoint.host?.lowercased() ?? "")
    }

    private struct PreparedUpload {
        let data: Data
        let mimeType: String
    }

    private static func preparedUpload(from data: Data) -> PreparedUpload {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return PreparedUpload(data: data, mimeType: "application/octet-stream")
        }
        let sourceType = CGImageSourceGetType(source) as String?
        let sourceMime = sourceType.flatMap { UTType($0)?.preferredMIMEType }
            ?? "application/octet-stream"
        if data.count <= 5 * 1024 * 1024,
           sourceMime == "image/jpeg" || sourceMime == "image/png" {
            return PreparedUpload(data: data, mimeType: sourceMime)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            return PreparedUpload(data: data, mimeType: sourceMime)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return PreparedUpload(data: data, mimeType: sourceMime)
        }
        return PreparedUpload(data: output as Data, mimeType: "image/jpeg")
        #else
        return PreparedUpload(data: data, mimeType: "application/octet-stream")
        #endif
    }
}

/// Default composition used by the view. Supplying a backend endpoint is
/// optional; this keeps previews, macOS, and offline use deterministic.
struct InBodyReportAnalysisService: InBodyReportAnalyzing, Sendable {
    private let remote: InBodyAIReportAnalyzer
    private let local = LocalInBodyReportAnalyzer()

    init(endpoint: URL? = InBodyAIReportAnalyzer.bundleEndpoint) {
        remote = InBodyAIReportAnalyzer(endpoint: endpoint)
    }

    var usesRemoteService: Bool { remote.isConfigured }

    func analyze(data: Data) async -> InBodyReportAnalysis {
        if remote.isConfigured {
            return await remote.analyze(data: data)
        }
        return await local.analyze(data: data)
    }
}

/// Small type-erased wrapper used by SwiftUI for test/preview injection.
struct AnyInBodyReportAnalyzer: InBodyReportAnalyzing, Sendable {
    private let operation: @Sendable (Data) async -> InBodyReportAnalysis
    let requiresRemoteUploadConsent: Bool

    init<A: InBodyReportAnalyzing>(
        _ analyzer: A,
        requiresRemoteUploadConsent: Bool = false
    ) {
        operation = { data in await analyzer.analyze(data: data) }
        self.requiresRemoteUploadConsent = requiresRemoteUploadConsent
    }

    func analyze(data: Data) async -> InBodyReportAnalysis {
        await operation(data)
    }

    static let local = AnyInBodyReportAnalyzer(LocalInBodyReportAnalyzer())

    static let live: AnyInBodyReportAnalyzer = {
        let service = InBodyReportAnalysisService()
        return AnyInBodyReportAnalyzer(
            service,
            requiresRemoteUploadConsent: service.usesRemoteService
        )
    }()
}

private struct InBodyAIRequest: Encodable {
    let imageBase64: String
    let mimeType: String
    let schemaVersion: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case schemaVersion = "schema_version"
    }
}

private struct InBodyAIEnvelope: Decodable {
    let data: InBodyAIResponse?
    let result: InBodyAIResponse?
    let analysis: InBodyAIResponse?
}

private struct InBodyAIResponse: Decodable {
    let measurementDate: Date?
    let heightCm: Double?
    let age: Double?
    let sex: String?
    let deviceModel: String?
    let weightKg: Double?
    let bodyFatKg: Double?
    let bodyFatPercent: Double?
    let skeletalMuscleKg: Double?
    let visceralFatLevel: Double?
    let bmi: Double?
    let score: Double?
    let waistHipRatio: Double?
    let totalBodyWaterL: Double?
    let proteinKg: Double?
    let mineralKg: Double?
    let fatFreeMassKg: Double?
    let bodyCellMassKg: Double?
    let basalMetabolicRate: Double?
    let smiKgPerM2: Double?
    let recognizedText: String?
    let matchedFieldCount: Int?
    let confidence: Double?
    let parserVersion: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case measurementDate
        case measurementDateSnake = "measurement_date"
        case measuredAt
        case measuredAtSnake = "measured_at"
        case testDate
        case testDateSnake = "test_date"
        case date
        case heightCm
        case heightCmSnake = "height_cm"
        case height
        case age
        case sex, gender
        case deviceModel
        case deviceModelSnake = "device_model"
        case model
        case weightKg
        case weightKgSnake = "weight_kg"
        case weight
        case bodyFatKg
        case bodyFatKgSnake = "body_fat_kg"
        case bodyFatMassKg
        case bodyFatMassKgSnake = "body_fat_mass_kg"
        case bodyFatMass
        case bodyFatPercent
        case bodyFatPercentSnake = "body_fat_percent"
        case bodyFatPercentage
        case bodyFatPercentageSnake = "body_fat_percentage"
        case bodyFat
        case skeletalMuscleKg
        case skeletalMuscleKgSnake = "skeletal_muscle_kg"
        case skeletalMuscleMassKg
        case skeletalMuscleMassKgSnake = "skeletal_muscle_mass_kg"
        case skeletalMuscle
        case visceralFatLevel
        case visceralFatLevelSnake = "visceral_fat_level"
        case visceralFat
        case bmi, score
        case waistHipRatio
        case waistHipRatioSnake = "waist_hip_ratio"
        case whr
        case totalBodyWaterL
        case totalBodyWaterLSnake = "total_body_water_l"
        case bodyWaterL
        case bodyWaterLSnake = "body_water_l"
        case totalBodyWater
        case totalBodyWaterSnake = "total_body_water"
        case proteinKg
        case proteinKgSnake = "protein_kg"
        case protein
        case mineralKg
        case mineralKgSnake = "mineral_kg"
        case mineral
        case minerals
        case fatFreeMassKg
        case fatFreeMassKgSnake = "fat_free_mass_kg"
        case fatFreeMass
        case bodyCellMassKg
        case bodyCellMassKgSnake = "body_cell_mass_kg"
        case bodyCellMass
        case basalMetabolicRate
        case basalMetabolicRateSnake = "basal_metabolic_rate"
        case basalMetabolicRateKcal
        case basalMetabolicRateKcalSnake = "basal_metabolic_rate_kcal"
        case bmr
        case bmrKcalSnake = "bmr_kcal"
        case smiKgPerM2
        case smiKgPerM2Snake = "smi_kg_per_m2"
        case smiKgM2Snake = "smi_kg_m2"
        case smi
        case recognizedText
        case recognizedTextSnake = "recognized_text"
        case text, rawText
        case matchedFieldCount
        case matchedFieldCountSnake = "matched_field_count"
        case confidence
        case parserVersion
        case parserVersionSnake = "parser_version"
        case message, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        measurementDate = Self.date(container, keys: [.measurementDate, .measurementDateSnake, .measuredAt, .measuredAtSnake, .testDate, .testDateSnake, .date])
        heightCm = Self.number(container, keys: [.heightCm, .heightCmSnake, .height])
        age = Self.number(container, keys: [.age])
        sex = Self.string(container, keys: [.sex, .gender])
        deviceModel = Self.string(container, keys: [.deviceModel, .deviceModelSnake, .model])
        weightKg = Self.number(container, keys: [.weightKg, .weightKgSnake, .weight])
        bodyFatKg = Self.number(container, keys: [.bodyFatKg, .bodyFatKgSnake, .bodyFatMassKg, .bodyFatMassKgSnake, .bodyFatMass])
        bodyFatPercent = Self.number(container, keys: [.bodyFatPercent, .bodyFatPercentSnake, .bodyFatPercentage, .bodyFatPercentageSnake, .bodyFat])
        skeletalMuscleKg = Self.number(container, keys: [.skeletalMuscleKg, .skeletalMuscleKgSnake, .skeletalMuscleMassKg, .skeletalMuscleMassKgSnake, .skeletalMuscle])
        visceralFatLevel = Self.number(container, keys: [.visceralFatLevel, .visceralFatLevelSnake, .visceralFat])
        bmi = Self.number(container, keys: [.bmi])
        score = Self.number(container, keys: [.score])
        waistHipRatio = Self.number(container, keys: [.waistHipRatio, .waistHipRatioSnake, .whr])
        totalBodyWaterL = Self.number(container, keys: [.totalBodyWaterL, .totalBodyWaterLSnake, .bodyWaterL, .bodyWaterLSnake, .totalBodyWater, .totalBodyWaterSnake])
        proteinKg = Self.number(container, keys: [.proteinKg, .proteinKgSnake, .protein])
        mineralKg = Self.number(container, keys: [.mineralKg, .mineralKgSnake, .mineral, .minerals])
        fatFreeMassKg = Self.number(container, keys: [.fatFreeMassKg, .fatFreeMassKgSnake, .fatFreeMass])
        bodyCellMassKg = Self.number(container, keys: [.bodyCellMassKg, .bodyCellMassKgSnake, .bodyCellMass])
        basalMetabolicRate = Self.number(container, keys: [.basalMetabolicRate, .basalMetabolicRateSnake, .basalMetabolicRateKcal, .basalMetabolicRateKcalSnake, .bmr, .bmrKcalSnake])
        smiKgPerM2 = Self.number(container, keys: [.smiKgPerM2, .smiKgPerM2Snake, .smiKgM2Snake, .smi])
        recognizedText = Self.string(container, keys: [.recognizedText, .recognizedTextSnake, .text, .rawText])
        matchedFieldCount = (try? container.decode(Int.self, forKey: .matchedFieldCount))
            ?? (try? container.decode(Int.self, forKey: .matchedFieldCountSnake))
        confidence = Self.number(container, keys: [.confidence])
        parserVersion = Self.string(container, keys: [.parserVersion, .parserVersionSnake])
        message = Self.string(container, keys: [.message, .summary])
    }

    var hasRecognizedValue: Bool {
        measurementDate != nil || heightCm != nil || age != nil || sex != nil || deviceModel != nil
            || weightKg != nil || bodyFatKg != nil || bodyFatPercent != nil || skeletalMuscleKg != nil
            || visceralFatLevel != nil || bmi != nil || score != nil || waistHipRatio != nil
            || totalBodyWaterL != nil || proteinKg != nil || mineralKg != nil || fatFreeMassKg != nil
            || bodyCellMassKg != nil || basalMetabolicRate != nil || smiKgPerM2 != nil
    }

    var derivedPrimaryMatchedFieldCount: Int {
        [weightKg, bodyFatPercent, skeletalMuscleKg, visceralFatLevel, bmi, score].compactMap { $0 }.count
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Double? {
        for key in keys {
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let text = try? container.decode(String.self, forKey: key) {
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized) {
                    return value
                }
                let pattern = #"[-+]?\d{1,6}(?:\.\d+)?"#
                if let expression = try? NSRegularExpression(pattern: pattern),
                   let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
                   let range = Range(match.range, in: normalized),
                   let value = Double(normalized[range]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    private static func date(_ container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Date? {
        for key in keys {
            if let timestamp = try? container.decode(Double.self, forKey: key) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
                if let value = plausibleMeasurementDate(Date(timeIntervalSince1970: seconds)) {
                    return value
                }
            }
            guard let text = try? container.decode(String.self, forKey: key) else { continue }
            if let timestamp = Double(text) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
                if let value = plausibleMeasurementDate(Date(timeIntervalSince1970: seconds)) {
                    return value
                }
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = isoFormatter.date(from: text).flatMap(plausibleMeasurementDate) { return value }
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let value = isoFormatter.date(from: text).flatMap(plausibleMeasurementDate) { return value }

            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy.MM.dd, HH:mm", "yyyy.MM.dd HH:mm", "yyyy.MM.dd", "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "yyyy年M月d日 HH:mm", "yyyy年M月d日"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = format
                if let value = formatter.date(from: text).flatMap(plausibleMeasurementDate) { return value }
            }
        }
        return nil
    }

    private static func plausibleMeasurementDate(_ value: Date) -> Date? {
        let earliest = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
        guard value >= earliest, value <= Date().addingTimeInterval(5 * 60) else {
            return nil
        }
        return value
    }
}

private enum InBodyAIAnalysisError: Error {
    case badResponse
    case emptyResponse
}
