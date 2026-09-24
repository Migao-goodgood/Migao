import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// Sends prepared meal photos to the app's authenticated analysis backend.
/// Model-provider credentials never belong in the app or its Info.plist.
struct DietAIPhotoAnalyzer {
    let endpoint: URL?
    let session: URLSession
    let tokenProvider: @Sendable () async -> String?

    static let maxImageBytes = 8_000_000
    static let maxResponseBytes = 65_536

    init(
        endpoint: URL? = DietAIPhotoAnalyzer.configuredEndpoint(),
        session: URLSession = DietAIPhotoAnalyzer.makeSession(),
        tokenProvider: @escaping @Sendable () async -> String? = { await DietAIPhotoAnalyzer.defaultAccessToken() }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.tokenProvider = tokenProvider
    }

    var isConfigured: Bool { endpoint.map(Self.isValidEndpoint) ?? false }

    func analyze(request: DietPhotoAnalysisRequest) async -> DietPhotoAnalysisDraft {
        guard let endpoint, Self.isValidEndpoint(endpoint) else {
            return unavailable("AI 识图尚未开通，照片可以先保存。", date: request.date)
        }
        guard !request.imageData.isEmpty, request.imageData.count <= 6,
              request.imageData.allSatisfy(Self.isPreparedJPEG),
              request.imageData.reduce(0, { $0 + $1.count }) <= Self.maxImageBytes else {
            return unavailable("照片格式或大小不符合要求，请重新选择餐食照片。", date: request.date)
        }
        guard !Task.isCancelled else { return unavailable("已取消识图，照片可以先保存。", date: request.date) }
        guard let token = await tokenProvider(), Self.isValidToken(token) else {
            return unavailable("AI 识图尚未登录，照片可以先保存。", date: request.date)
        }
        guard !Task.isCancelled else { return unavailable("已取消识图，照片可以先保存。", date: request.date) }

        do {
            var httpRequest = URLRequest(url: endpoint)
            httpRequest.httpMethod = "POST"
            httpRequest.timeoutInterval = 45
            httpRequest.cachePolicy = .reloadIgnoringLocalCacheData
            httpRequest.httpShouldHandleCookies = false
            httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            httpRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            httpRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            httpRequest.httpBody = try JSONEncoder().encode(WireRequest(
                schema_version: "diet-1",
                images: request.imageData.map { WireImage(image_base64: $0.base64EncodedString(), mime_type: "image/jpeg") }
            ))

            // Do not forward photos or authorization to redirect destinations.
            let (data, response) = try await session.data(for: httpRequest, delegate: NoRedirectDelegate())
            guard !Task.isCancelled else { return unavailable("已取消识图，照片可以先保存。", date: request.date) }
            guard let httpResponse = response as? HTTPURLResponse else {
                return unavailable("识图服务暂时不可用，照片可以先保存。", date: request.date)
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return unavailable("AI 识图登录已失效，照片可以先保存。", date: request.date)
            }
            if httpResponse.statusCode == 429 {
                return unavailable("识图次数较多，请稍后重试；照片可以先保存。", date: request.date)
            }
            guard httpResponse.statusCode == 200,
                  httpResponse.mimeType?.lowercased() == "application/json",
                  !data.isEmpty, data.count <= Self.maxResponseBytes,
                  httpResponse.expectedContentLength <= Int64(Self.maxResponseBytes) else {
                return unavailable("识图服务返回异常，照片可以先保存。", date: request.date)
            }
            let result = try JSONDecoder().decode(WireResponse.self, from: data)
            guard result.schema_version == "diet-1", result.confidence.isFinite,
                  (0...1).contains(result.confidence),
                  result.portion_description.count <= 500, result.notes.count <= 1_000,
                  result.calories_kcal.map({ (0...20_000).contains($0) }) ?? true else {
                return unavailable("识图结果无效，照片可以先保存。", date: request.date)
            }
            guard result.is_food else {
                return unavailable("未识别到餐食，请选择清晰的餐食照片。", date: request.date)
            }
            guard result.confidence >= 0.45, let calories = result.calories_kcal else {
                return unavailable("这张照片暂时无法可靠估算热量，可换一张清晰照片。", date: request.date)
            }

            let details = [result.portion_description, result.notes]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return DietPhotoAnalysisDraft(
                mealType: Self.mealType(for: request.date),
                caloriesKcal: calories,
                confidence: result.confidence,
                sourceLabel: String((details.isEmpty ? "AI 估算 · 请按实际食用份量确认" : "AI 估算 · \(details)").prefix(240)),
                estimatedCaloriesKcal: calories,
                portionMultiplier: 1
            )
        } catch is CancellationError {
            return unavailable("已取消识图，照片可以先保存。", date: request.date)
        } catch let error as URLError {
            let message = error.code == .cancelled ? "已取消识图，照片可以先保存。"
                : error.code == .timedOut ? "识图超时，请稍后重试；照片可以先保存。"
                : "暂时无法连接识图服务，照片可以先保存。"
            return unavailable(message, date: request.date)
        } catch {
            return unavailable("识图结果暂时无法读取，照片可以先保存。", date: request.date)
        }
    }

    static func configuredEndpoint(bundle: Bundle = .main) -> URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["DIET_AI_ENDPOINT"] {
            return URL(string: override)
        }
        #endif
        guard let value = bundle.object(forInfoDictionaryKey: "DIET_AI_ENDPOINT") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: value)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 50
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    static func defaultAccessToken() async -> String? {
        #if DEBUG
        // Development scheme only. Release requires an injected app-session
        // token provider; no token is read from bundled settings or defaults.
        return ProcessInfo.processInfo.environment["DIET_AI_ACCESS_TOKEN"]
        #else
        return nil
        #endif
    }

    private static func isValidEndpoint(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { return false }
        if parts.scheme?.lowercased() == "https" { return true }
        #if DEBUG
        return parts.scheme?.lowercased() == "http"
            && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        #else
        return false
        #endif
    }

    private static func isValidToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8_192
            && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }

    private static func isPreparedJPEG(_ data: Data) -> Bool {
        guard data.count >= 4, data.count <= maxImageBytes,
              data.prefix(3) == Data([0xFF, 0xD8, 0xFF]), data.suffix(2) == Data([0xFF, 0xD9]) else { return false }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 6_000, height <= 6_000 else { return false }
        #endif
        return true
    }

    private func unavailable(_ message: String, date: Date) -> DietPhotoAnalysisDraft {
        DietPhotoAnalysisDraft(mealType: Self.mealType(for: date), sourceLabel: message)
    }

    private static func mealType(for date: Date) -> DietMealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }

    private struct WireRequest: Encodable {
        let schema_version: String
        let images: [WireImage]
    }

    private struct WireImage: Encodable {
        let image_base64: String
        let mime_type: String
    }

    private struct WireResponse: Decodable {
        let schema_version: String
        let is_food: Bool
        let calories_kcal: Int?
        let confidence: Double
        let portion_description: String
        let notes: String

        private enum CodingKeys: String, CodingKey {
            case schema_version, is_food, calories_kcal, confidence, portion_description, notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema_version = try container.decode(String.self, forKey: .schema_version)
            is_food = try container.decode(Bool.self, forKey: .is_food)
            // The key is required even when the value is unknown (JSON null).
            guard container.contains(.calories_kcal) else {
                throw DecodingError.keyNotFound(CodingKeys.calories_kcal, .init(codingPath: container.codingPath, debugDescription: "Missing calorie result"))
            }
            calories_kcal = try container.decodeIfPresent(Int.self, forKey: .calories_kcal)
            confidence = try container.decode(Double.self, forKey: .confidence)
            portion_description = try container.decode(String.self, forKey: .portion_description)
            notes = try container.decode(String.self, forKey: .notes)
        }
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }
}
