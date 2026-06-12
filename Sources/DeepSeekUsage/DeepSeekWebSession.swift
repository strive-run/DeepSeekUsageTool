import Foundation
import WebKit

@MainActor
final class DeepSeekWebSession {
    let webView: WKWebView

    private let scriptBridge = DeepSeekScriptBridge()
    private var hasLoadedUsagePage = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(Self.authorizationCaptureScript)
        configuration.userContentController.add(scriptBridge, name: DeepSeekScriptBridge.messageHandlerName)
        self.webView = WKWebView(frame: .zero, configuration: configuration)
    }

    var isReady: Bool {
        webView.url?.host?.hasSuffix("platform.deepseek.com") == true
    }

    func loadUsagePageIfNeeded() {
        guard !hasLoadedUsagePage || webView.url == nil else { return }
        hasLoadedUsagePage = true
        if let url = URL(string: "https://platform.deepseek.com/usage") {
            webView.load(URLRequest(url: url))
        }
    }

    func fetchSnapshot(now: Date = Date()) async throws -> UsageSnapshot {
        try await waitForPlatformContext()
        await allowAuthorizationCaptureToSettle()

        let summaryEnvelope: APIEnvelope<UserSummaryPayload> = try await fetchEnvelope(
            path: "/api/v0/users/get_user_summary"
        )

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        guard let year = components.year, let month = components.month else {
            throw DeepSeekError.invalidURL
        }

        let amountEnvelope: APIEnvelope<UsageAmountPayload> = try await fetchEnvelope(
            path: "/api/v0/usage/amount",
            queryItems: [
                URLQueryItem(name: "month", value: String(month)),
                URLQueryItem(name: "year", value: String(year))
            ]
        )

        let costEnvelope: APIEnvelope<[UsageCostPayload]> = try await fetchEnvelope(
            path: "/api/v0/usage/cost",
            queryItems: [
                URLQueryItem(name: "month", value: String(month)),
                URLQueryItem(name: "year", value: String(year))
            ]
        )

        let costPayload = costEnvelope.data.bizData.first ?? UsageCostPayload(currency: "CNY", total: [], days: [])
        let wallet = UsageAggregator.walletSummary(from: summaryEnvelope.data.bizData)
        let daily = UsageAggregator.dailyPoints(
            costPayload: costPayload,
            amountPayload: amountEnvelope.data.bizData,
            today: now
        )

        return UsageSnapshot(summary: wallet, dailyPoints: daily, lastUpdated: Date())
    }

    private func fetchEnvelope<Payload: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> APIEnvelope<Payload> {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let relativeURL = components.string else { throw DeepSeekError.invalidURL }

        let requestId = UUID().uuidString
        let responseTask = Task { try await scriptBridge.waitForResponse(requestId: requestId) }
        do {
            try await webView.evaluateJavaScript(Self.fetchScript(requestId: requestId, relativeURL: relativeURL))
        } catch {
            scriptBridge.cancel(requestId: requestId)
            responseTask.cancel()
            throw error
        }
        let response = try await responseTask.value
        print("DeepSeek fetch \(path) status=\(response.status) ok=\(response.ok) bytes=\(response.body.count)")

        guard (200..<300).contains(response.status) else {
            if response.status == 401 || response.status == 403 {
                throw DeepSeekError.unauthorized
            }
            throw DeepSeekError.httpStatus(response.status)
        }

        let bodyData = Data(response.body.utf8)
        try DeepSeekResponseValidator.validateBusinessEnvelope(bodyData)
        return try JSONDecoder().decode(APIEnvelope<Payload>.self, from: bodyData)
    }

    private func waitForPlatformContext() async throws {
        loadUsagePageIfNeeded()
        for _ in 0..<80 {
            if isReady, !webView.isLoading {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw DeepSeekError.businessError(code: -1, message: "正在等待 DeepSeek 登录会话同步。")
    }

    private func allowAuthorizationCaptureToSettle() async {
        for _ in 0..<4 {
            if !((try? await webView.evaluateJavaScript("window.__deepSeekUsageAuthToken || ''")) as? String ?? "").isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    static func fetchScript(requestId: String, relativeURL: String) -> String {
        let encodedRequestId = jsString(requestId)
        let encodedURL = jsString(relativeURL)
        return """
        (() => {
          const requestId = \(encodedRequestId);
          const send = (payload) => {
            try {
              window.webkit.messageHandlers.deepSeekUsage.postMessage(Object.assign({ requestId }, payload));
            } catch (_) {}
          };
          const token = window.__deepSeekUsageAuthToken || "";
          const headers = { "Accept": "*/*", "X-App-Version": "1.0.0" };
          if (token) headers["Authorization"] = token.startsWith("Bearer ") ? token : `Bearer ${token}`;
          fetch(\(encodedURL), {
            method: "GET",
            credentials: "include",
            headers
          })
            .then(async (response) => {
              const body = await response.text();
              send({ status: response.status, ok: response.ok, body });
            })
            .catch((error) => {
              send({ error: String(error && error.message ? error.message : error) });
            });
          return undefined;
        })();
        """
    }

    static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }

    private static let authorizationCaptureScript = WKUserScript(
        source: """
        (() => {
          if (window.__deepSeekUsageAuthCaptureInstalled) return;
          window.__deepSeekUsageAuthCaptureInstalled = true;
          window.__deepSeekUsageAuthToken = window.__deepSeekUsageAuthToken || "";
          const remember = (value) => {
            if (typeof value !== "string") return;
            if (/^Bearer\\s+/i.test(value)) window.__deepSeekUsageAuthToken = value;
          };
          const readHeaders = (headers) => {
            if (!headers) return;
            try {
              if (headers instanceof Headers) {
                remember(headers.get("Authorization") || headers.get("authorization"));
              } else if (Array.isArray(headers)) {
                for (const pair of headers) {
                  if (pair && String(pair[0]).toLowerCase() === "authorization") remember(pair[1]);
                }
              } else if (typeof headers === "object") {
                remember(headers.Authorization || headers.authorization);
              }
            } catch (_) {}
          };
          const originalFetch = window.fetch;
          window.fetch = function(input, init) {
            try {
              if (input && input.headers) readHeaders(input.headers);
              if (init && init.headers) readHeaders(init.headers);
            } catch (_) {}
            return originalFetch.apply(this, arguments);
          };
          const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
          XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            try {
              if (String(name).toLowerCase() === "authorization") remember(value);
            } catch (_) {}
            return originalSetRequestHeader.apply(this, arguments);
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
}

struct WebFetchResponse: Decodable, Equatable {
    var status: Int
    var ok: Bool
    var body: String
    var error: String?

    var errorOrNil: DeepSeekError? {
        guard let error, !error.isEmpty else { return nil }
        return .businessError(code: -1, message: error)
    }
}

@MainActor
final class DeepSeekScriptBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "deepSeekUsage"

    private struct PendingRequest {
        var continuation: CheckedContinuation<WebFetchResponse, Error>
        var timeoutTask: Task<Void, Never>
    }

    private var pendingRequests: [String: PendingRequest] = [:]

    func waitForResponse(requestId: String, timeout: Duration = .seconds(20)) async throws -> WebFetchResponse {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.cancel(
                        requestId: requestId,
                        throwing: DeepSeekError.businessError(code: -1, message: "DeepSeek WebView 请求超时。")
                    )
                }
                pendingRequests[requestId] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(requestId: requestId)
            }
        }
    }

    func cancel(requestId: String, throwing error: Error = CancellationError()) {
        guard let pending = pendingRequests.removeValue(forKey: requestId) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: error)
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.receive(message.body)
        }
    }

    func receive(_ body: Any) {
        guard let response = Self.decodeResponse(from: body),
              let pending = pendingRequests.removeValue(forKey: response.requestId) else {
            return
        }

        pending.timeoutTask.cancel()
        if let error = response.response.errorOrNil {
            pending.continuation.resume(throwing: error)
        } else {
            pending.continuation.resume(returning: response.response)
        }
    }

    static func decodeResponse(from body: Any) -> (requestId: String, response: WebFetchResponse)? {
        guard let dictionary = body as? [String: Any],
              let requestId = dictionary["requestId"] as? String else {
            return nil
        }

        if let error = dictionary["error"] as? String {
            return (requestId, WebFetchResponse(status: 0, ok: false, body: "", error: error))
        }

        guard let status = dictionary["status"] as? Int,
              let ok = dictionary["ok"] as? Bool,
              let body = dictionary["body"] as? String else {
            return nil
        }

        return (requestId, WebFetchResponse(status: status, ok: ok, body: body, error: nil))
    }
}
