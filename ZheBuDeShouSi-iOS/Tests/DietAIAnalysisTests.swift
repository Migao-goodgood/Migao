import Foundation
import AppKit

/// Offline transport and provenance contracts. Every HTTP request is caught
/// by URLProtocol; no photos, tokens or paid model requests leave the process.
@main
struct DietAIAnalysisTests {
    final class MockProtocol: URLProtocol {
        struct Reply {
            var status = 200
            var mime = "application/json"
            var data: Data
            var error: Error?
        }

        static let lock = NSLock()
        static var handler: ((URLRequest) -> Reply)?
        static var requestCount = 0

        static func install(_ handler: @escaping (URLRequest) -> Reply) {
            lock.lock()
            defer { lock.unlock() }
            Self.handler = handler
            requestCount = 0
        }

        static var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCount
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lock.lock()
            Self.requestCount += 1
            let handler = Self.handler
            Self.lock.unlock()
            guard let handler else { preconditionFailure("Unconfigured HTTP request") }
            let reply = handler(request)
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.mime])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), message, file: file, line: line)
    }

    static var goodResponse: [String: Any] {
        ["schema_version": "diet-1", "is_food": true, "calories_kcal": 480,
         "confidence": 0.82, "portion_description": "照片中一份", "notes": "按可见份量估算"]
    }

    static func response(_ fields: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: fields) }

    static func jpeg() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 240, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func analyzer(endpoint: URL? = URL(string: "https://example.invalid/api/diet/analyze"), token: String? = "test-app-session") -> DietAIPhotoAnalyzer {
        DietAIPhotoAnalyzer(endpoint: endpoint, session: session(), tokenProvider: { token })
    }

    static func request(_ data: [Data]? = nil) -> DietPhotoAnalysisRequest {
        DietPhotoAnalysisRequest(date: .now, imageData: data ?? [jpeg()])
    }

    static func requestBody(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { preconditionFailure("Missing JSON body") }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    @MainActor
    static func main() async throws {
        await validTransport()
        await configurationAndAuth()
        await invalidImages()
        await uncertaintyAndZero()
        await malformedResults()
        await serverFailures()
        try legacyAndRoundTrip()
        try provenancePersistence()
        print("PASS: Diet AI transport/provenance — 8 contract groups (offline)")
    }

    static func validTransport() async {
        let image = jpeg()
        MockProtocol.install { http in
            require(http.httpMethod == "POST", "Must POST meal photos")
            require(http.value(forHTTPHeaderField: "Authorization") == "Bearer test-app-session", "Use only app-session bearer auth")
            require(http.value(forHTTPHeaderField: "Content-Type") == "application/json", "JSON request")
            require(http.httpShouldHandleCookies == false, "No browser/session cookie upload")
            let object = try! JSONSerialization.jsonObject(with: requestBody(http)) as! [String: Any]
            require(Set(object.keys) == ["schema_version", "images"], "Only versioned photo payload, no private date or metadata")
            require(object["schema_version"] as? String == "diet-1", "Schema version")
            let images = object["images"] as! [[String: Any]]
            require(images.count == 2, "Keep batch together")
            require(images.allSatisfy { $0["mime_type"] as? String == "image/jpeg" && Data(base64Encoded: $0["image_base64"] as! String) == image }, "JPEG bytes and mime")
            return .init(data: response(goodResponse))
        }
        let result = await analyzer().analyze(request: request([image, image]))
        require(result.caloriesKcal == 480 && result.estimatedCaloriesKcal == 480 && result.portionMultiplier == 1, "Keep base estimate and original portion")
        require(result.isCalorieEstimate && result.confidence == 0.82, "AI provenance")
        require(result.title.isEmpty && result.foods.isEmpty, "Do not add unwanted food labels")
        require(MockProtocol.count == 1, "One backend call per batch")
    }

    static func configurationAndAuth() async {
        MockProtocol.install { _ in preconditionFailure("Invalid endpoint/auth must never send photos") }
        let unsafe = ["http://example.invalid/api", "https://user:secret@example.invalid/api",
            "https://example.invalid/api?token=secret", "https://example.invalid/api#fragment", "file:///tmp/api"]
        for raw in unsafe {
            let client = analyzer(endpoint: URL(string: raw))
            require(!client.isConfigured, "Reject unsafe endpoint \(raw)")
            let result = await client.analyze(request: request())
            require(result.caloriesKcal == nil && !result.isCalorieEstimate, "Invalid config has no invented estimate")
        }
        let missing = await analyzer(endpoint: nil).analyze(request: request())
        require(missing.sourceLabel.contains("未开通"), "Explain unavailable service")
        for token: String? in [nil, "", "bad\ntoken", "token with spaces"] {
            let result = await analyzer(token: token).analyze(request: request())
            require(result.sourceLabel.contains("未登录") && result.caloriesKcal == nil, "Auth errors preserve unknown calories")
        }
        #if DEBUG
        require(analyzer(endpoint: URL(string: "http://127.0.0.1:8787/api/diet/analyze")).isConfigured, "Allow local developer fixture only in Debug")
        #else
        require(!analyzer(endpoint: URL(string: "http://127.0.0.1:8787/api/diet/analyze")).isConfigured, "Release forbids localhost HTTP")
        let releaseToken = await DietAIPhotoAnalyzer.defaultAccessToken()
        require(releaseToken == nil, "Release must not read development credentials")
        #endif
        require(MockProtocol.count == 0, "No photos uploaded before valid config/auth")
    }

    static func invalidImages() async {
        MockProtocol.install { _ in preconditionFailure("Invalid images must not send") }
        let cases: [[Data]] = [[], [Data()], [Data([0xFF, 0xD8, 0xFF, 0xD9])],
            [Data("not a jpeg".utf8)], Array(repeating: jpeg(), count: 7),
            [Data(repeating: 0, count: DietAIPhotoAnalyzer.maxImageBytes + 1)]]
        for images in cases {
            let result = await analyzer().analyze(request: request(images))
            require(result.caloriesKcal == nil && result.sourceLabel.contains("照片"), "Invalid image must remain unknown")
        }
        require(MockProtocol.count == 0, "Invalid batch does not upload")
    }

    static func uncertaintyAndZero() async {
        for (isFood, confidence, calories) in [(false, 0.9, 500), (true, 0.44, 600)] {
            var object = goodResponse
            object["is_food"] = isFood
            object["confidence"] = confidence
            object["calories_kcal"] = calories
            MockProtocol.install { _ in .init(data: response(object)) }
            let result = await analyzer().analyze(request: request())
            require(result.caloriesKcal == nil && !result.isCalorieEstimate, "Non-food/uncertain estimate stays unknown, never zero")
        }
        var zero = goodResponse
        zero["calories_kcal"] = 0
        zero["confidence"] = 0.45
        MockProtocol.install { _ in .init(data: response(zero)) }
        let result = await analyzer().analyze(request: request())
        require(result.caloriesKcal == 0 && result.isCalorieEstimate, "Genuine zero differs from missing")
        var absent = goodResponse
        absent["calories_kcal"] = NSNull()
        MockProtocol.install { _ in .init(data: response(absent)) }
        let nullResult = await analyzer().analyze(request: request())
        require(nullResult.caloriesKcal == nil, "Null kcal stays nil")
    }

    static func malformedResults() async {
        var cases = [[String: Any]]()
        for (key, value): (String, Any) in [("schema_version", "diet-2"), ("is_food", "true"),
            ("calories_kcal", -1), ("calories_kcal", 20_001), ("calories_kcal", "500"),
            ("calories_kcal", 123.5), ("confidence", -0.1), ("confidence", 1.1),
            ("portion_description", 5), ("notes", String(repeating: "x", count: 1_001))] {
            var object = goodResponse
            object[key] = value
            cases.append(object)
        }
        var missingKey = goodResponse
        missingKey.removeValue(forKey: "calories_kcal")
        cases.append(missingKey)
        for object in cases {
            MockProtocol.install { _ in .init(data: response(object)) }
            let result = await analyzer().analyze(request: request())
            require(result.caloriesKcal == nil && !result.isCalorieEstimate, "Malformed response never enters totals")
        }
        for data in [Data(), Data("bad json".utf8), Data(repeating: 32, count: DietAIPhotoAnalyzer.maxResponseBytes + 1)] {
            MockProtocol.install { _ in .init(data: data) }
            let invalidResult = await analyzer().analyze(request: request())
            require(invalidResult.caloriesKcal == nil, "Reject empty/invalid/oversized response")
        }
        MockProtocol.install { _ in .init(mime: "text/html", data: response(goodResponse)) }
        let wrongMIMEResult = await analyzer().analyze(request: request())
        require(wrongMIMEResult.caloriesKcal == nil, "Reject wrong response MIME")
    }

    static func serverFailures() async {
        for status in [301, 401, 403, 429, 500, 503] {
            MockProtocol.install { _ in .init(status: status, data: response(goodResponse)) }
            let result = await analyzer().analyze(request: request())
            require(result.caloriesKcal == nil && !result.isCalorieEstimate, "HTTP errors cannot become estimates")
            if status == 401 || status == 403 { require(result.sourceLabel.contains("登录"), "Actionable auth status") }
        }
        for code in [URLError.timedOut, .notConnectedToInternet, .cancelled] {
            MockProtocol.install { _ in .init(data: Data(), error: URLError(code)) }
            let result = await analyzer().analyze(request: request())
            require(result.caloriesKcal == nil && result.sourceLabel.contains("照片可以先保存"), "Network failure never blocks photo record")
        }
    }

    static func legacyAndRoundTrip() throws {
        let oldDraft = DietPhotoAnalysisDraft(mealType: .lunch, caloriesKcal: 500, sourceLabel: "设备端文字识别")
        let restoredDraft = try JSONDecoder().decode(DietPhotoAnalysisDraft.self, from: JSONEncoder().encode(oldDraft))
        require(restoredDraft.estimatedCaloriesKcal == nil && restoredDraft.portionMultiplier == nil && !restoredDraft.isCalorieEstimate, "Old OCR drafts are not inferred AI estimates")
        let oldMeal = try JSONDecoder().decode(MealRecord.self, from: Data(#"{"title":"旧餐食","calories":500,"source":"ai"}"#.utf8))
        require(oldMeal.caloriesKcal == 500 && !oldMeal.isCalorieEstimate && oldMeal.estimatedCaloriesKcal == nil, "Legacy source alone cannot imply AI estimate")
        let estimated = MealRecord(caloriesKcal: 250, estimatedCaloriesKcal: 500, portionMultiplier: 0.5)
        let restored = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(estimated))
        require(restored == estimated && restored.isCalorieEstimate, "New provenance round-trips")
        var corrupt = estimated
        corrupt.portionMultiplier = 1.5
        require(!corrupt.isCalorieEstimate && corrupt.normalized().estimatedCaloriesKcal == nil, "Invalid persisted provenance is removed without inventing data")
    }

    @MainActor
    static func provenancePersistence() throws {
        let suiteName = "Migao.DietAITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DietStore(defaults: defaults, migrateLegacy: false)
        let capture = DietCaptureDraft(analysis: DietPhotoAnalysisDraft(mealType: .lunch, caloriesKcal: 300,
            sourceLabel: "AI 估算", estimatedCaloriesKcal: 600, portionMultiplier: 0.5), images: [MealImageMetadata(data: jpeg())], source: .ai)
        require(store.saveDraft(capture), "Save estimate review")
        require(!store.summary(for: capture.date).hasEstimatedCalories, "Drafts stay outside confirmed totals")
        let meal = store.confirmDraft(id: capture.id)!
        require(meal.isCalorieEstimate && meal.estimatedCaloriesKcal == 600 && meal.portionMultiplier == 0.5, "Confirmation keeps verified estimate provenance")
        require(store.summary(for: capture.date).hasEstimatedCalories, "Day indicates estimated total")
        let reloaded = DietStore(defaults: defaults, migrateLegacy: false)
        require(reloaded.record(id: meal.id)?.isCalorieEstimate == true, "Estimate survives app restart")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: capture.date)!
        require(store.updateMeal(id: meal.id, date: yesterday, mealType: .dinner, title: "", caloriesKcal: 300), "Date/meal slot edits save")
        require(store.record(id: meal.id)?.isCalorieEstimate == true, "Date-only edit preserves provenance")
        require(store.updateMeal(id: meal.id, date: yesterday, mealType: .dinner, title: "", caloriesKcal: 450), "Manual calorie override saves")
        require(store.record(id: meal.id)?.estimatedCaloriesKcal == nil && store.record(id: meal.id)?.portionMultiplier == nil, "Manual value removes stale estimate")
        require(!store.summary(for: yesterday).hasEstimatedCalories, "Manual calorie total is not labeled AI")
        let second = DietCaptureDraft(analysis: capture.analysis, images: capture.images)
        require(store.saveDraft(second), "Second estimate save")
        let secondMeal = store.confirmDraft(id: second.id)!
        require(store.updateMeal(id: secondMeal.id, date: secondMeal.date, mealType: .lunch, title: "", caloriesKcal: nil), "Clear known total")
        require(store.record(id: secondMeal.id)?.caloriesKcal == nil && store.record(id: secondMeal.id)?.estimatedCaloriesKcal == nil, "Clearing total also clears provenance")
        for multiplier in [0.1, 2.1, Double.nan, 1] {
            var invalid = DietCaptureDraft(analysis: capture.analysis, images: capture.images)
            invalid.analysis.portionMultiplier = multiplier
            require(!store.saveDraft(invalid), "Reject invalid/mismatched estimate metadata")
            require(store.draft(id: invalid.id) == nil, "Bad provenance never persists")
        }
    }
}
