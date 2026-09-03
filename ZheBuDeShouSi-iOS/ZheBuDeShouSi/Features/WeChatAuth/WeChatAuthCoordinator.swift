import Combine
import Foundation

#if os(iOS)
import UIKit
#endif

/// Client-side configuration for the WeChat Open Platform hand-off.
///
/// The app never stores an AppSecret or exchanges an authorization code
/// directly. A product-owned HTTPS endpoint performs that exchange and then
/// redirects to the callback scheme registered by the app.
struct WeChatAuthConfiguration: Equatable, Sendable {
    let appID: String?
    let authorizationURL: URL?
    let callbackScheme: String

    static var fromBundle: WeChatAuthConfiguration {
        let bundle = Bundle.main
        let appID = (bundle.object(forInfoDictionaryKey: "WECHAT_APP_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = (bundle.object(forInfoDictionaryKey: "WECHAT_AUTH_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = ((bundle.object(forInfoDictionaryKey: "WECHAT_CALLBACK_SCHEME") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? "zhebudeshousi"

        return WeChatAuthConfiguration(
            appID: appID?.isEmpty == true ? nil : appID,
            authorizationURL: rawURL.flatMap(URL.init(string:)),
            callbackScheme: callback.isEmpty ? "zhebudeshousi" : callback
        )
    }

    var isConfigured: Bool {
        guard let appID, !appID.isEmpty,
              let authorizationURL,
              authorizationURL.scheme?.lowercased() == "https",
              !callbackScheme.isEmpty else { return false }
        return true
    }

    /// Adds the app id and one-time state to the product-owned authorization
    /// endpoint. The endpoint keeps the AppSecret and code exchange server-side.
    func authorizationURL(for state: String) -> URL? {
        guard let authorizationURL else { return nil }
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { item in item.name == "state" || item.name == "app_id" }
        if let appID, !appID.isEmpty {
            queryItems.append(URLQueryItem(name: "app_id", value: appID))
        }
        queryItems.append(URLQueryItem(name: "state", value: state))
        components?.queryItems = queryItems
        return components?.url
    }
}

enum WeChatAuthState: Equatable, Sendable {
    case idle
    case unavailable
    case opening
    case awaitingCallback
    case authenticated
    case failed

    var message: String {
        switch self {
        case .idle: return ""
        case .unavailable: return "微信登录尚未配置"
        case .opening: return "正在打开授权页面"
        case .awaitingCallback: return "请完成微信授权后返回应用"
        case .authenticated: return "微信授权完成"
        case .failed: return "微信授权未完成，请重试"
        }
    }
}

/// Owns the login hand-off and callback state; the SwiftUI sheet only renders
/// this state and never handles URL schemes or credentials itself.
@MainActor
final class WeChatAuthCoordinator: ObservableObject {
    @Published private(set) var state: WeChatAuthState = .idle

    let configuration: WeChatAuthConfiguration

    private var pendingState: String?
    private var pendingStateExpiresAt: Date?
    private let stateLifetime: TimeInterval = 5 * 60

    init(configuration: WeChatAuthConfiguration = .fromBundle) {
        self.configuration = configuration
    }

    var isConfigured: Bool { configuration.isConfigured }
    var statusMessage: String { state.message }

    func beginLogin() {
        guard configuration.isConfigured,
              let authorizationURL = configuration.authorizationURL(for: UUID().uuidString) else {
            state = .unavailable
            return
        }

        let stateValue = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "state" })?
            .value
        guard let stateValue, !stateValue.isEmpty else {
            state = .failed
            return
        }
        pendingState = stateValue
        pendingStateExpiresAt = Date().addingTimeInterval(stateLifetime)

        #if os(iOS)
        state = .opening
        UIApplication.shared.open(authorizationURL, options: [:]) { [weak self] opened in
            Task { @MainActor in
                guard let self else { return }
                if opened {
                    self.state = .awaitingCallback
                } else {
                    self.clearPendingRequest()
                    self.state = .failed
                }
            }
        }
        #else
        clearPendingRequest()
        state = .failed
        #endif
    }

    /// Handles the app callback after the product backend has exchanged the
    /// WeChat code. No access token is persisted in this client.
    func handleCallback(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(configuration.callbackScheme) == .orderedSame else {
            return
        }

        guard let pendingState,
              let pendingStateExpiresAt,
              pendingStateExpiresAt > Date() else {
            state = .failed
            return
        }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard query.first(where: { $0.name == "state" })?.value == pendingState else {
            clearPendingRequest()
            state = .failed
            return
        }

        if query.first(where: { $0.name == "error" })?.value != nil {
            clearPendingRequest()
            state = .failed
            return
        }

        let status = query.first(where: { $0.name == "status" })?.value?.lowercased()
        let ticket = query.first(where: { $0.name == "ticket" })?.value
            ?? query.first(where: { $0.name == "session" })?.value
        if status == "success", let ticket, !ticket.isEmpty {
            // `ticket` must be a short-lived, one-time value minted by the
            // product backend after it exchanges the WeChat code. This client
            // never accepts or persists an access token.
            clearPendingRequest()
            state = .authenticated
        } else {
            clearPendingRequest()
            state = .failed
        }
    }

    func reset() {
        clearPendingRequest()
        state = .idle
    }

    private func clearPendingRequest() {
        pendingState = nil
        pendingStateExpiresAt = nil
    }
}
