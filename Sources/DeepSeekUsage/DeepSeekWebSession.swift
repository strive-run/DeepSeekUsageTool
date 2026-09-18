import Foundation
import WebKit

private func debugLog(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@MainActor
final class DeepSeekWebSession {
    let webView: WKWebView

    private let scriptBridge = DeepSeekScriptBridge()
    private var hasLoadedUsagePage = false
    private var authorizationToken: String?
    private static let deviceID = UUID().uuidString

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
        debugLog("[debug] fetchSnapshot begin")
        try await waitForPlatformContext()
        await allowAuthorizationCaptureToSettle()

        guard let token = await readAuthorizationToken(), !token.isEmpty else {
            throw DeepSeekError.businessError(code: -1, message: "未获取到 DeepSeek 登录令牌，请重新登录。")
        }
        authorizationToken = token
        debugLog("token ready, prefix=\(token.prefix(12)) len=\(token.count)")

        let summaryEnvelope: APIEnvelope<UserSummaryPayload> = try await fetchEnvelope(
            path: "/api/v0/users/get_user_summary"
        )

        let calendar = Calendar(identifier: .gregorian)
        let todayStart = calendar.startOfDay(for: now)
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: todayStart)
        ) else {
            throw DeepSeekError.invalidURL
        }
        let endDate = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let start = Int64(monthStart.timeIntervalSince1970)
        let end = Int64(endDate.timeIntervalSince1970)
        let tz = Int64(TimeZone.current.secondsFromGMT())

        let amountEnvelope: APIEnvelope<UsageByApiKeyAmountPayload> = try await fetchEnvelope(
            path: "/api/v0/usage/by_api_key/amount",
            queryItems: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "end", value: String(end)),
                URLQueryItem(name: "tz", value: String(tz))
            ]
        )

        let costEnvelope: APIEnvelope<UsageByApiKeyCostPayload> = try await fetchEnvelope(
            path: "/api/v0/usage/by_api_key/cost",
            queryItems: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "end", value: String(end)),
                URLQueryItem(name: "tz", value: String(tz))
            ]
        )

        let daily = UsageAggregator.dailyPoints(
            byApiKeyCostPayload: costEnvelope.data.bizData,
            byApiKeyAmountPayload: amountEnvelope.data.bizData,
            today: now
        )

        let monthlyCostCNY = daily.reduce(Decimal.zero) { $0 + $1.costCNY }
        let wallet = UsageAggregator.walletSummary(
            from: summaryEnvelope.data.bizData,
            monthlyCostCNY: monthlyCostCNY
        )

        return UsageSnapshot(summary: wallet, dailyPoints: daily, lastUpdated: Date())
    }

    private func readAuthorizationToken() async -> String? {
        let value = ((try? await webView.evaluateJavaScript(
            "window.__deepSeekUsageReadToken ? window.__deepSeekUsageReadToken() : ''"
        )) as? String ?? "")
        return value.isEmpty ? nil : value
    }

    private func fetchEnvelope<Payload: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> APIEnvelope<Payload> {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "platform.deepseek.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw DeepSeekError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let token = authorizationToken {
            request.setValue(
                token.hasPrefix("Bearer ") ? token : "Bearer \(token)",
                forHTTPHeaderField: "Authorization"
            )
        }
        request.setValue("web", forHTTPHeaderField: "x-client-platform")
        request.setValue("1.0.0", forHTTPHeaderField: "x-client-version")
        request.setValue("com.deepseek.chat", forHTTPHeaderField: "x-client-bundle-id")
        request.setValue("zh-CN", forHTTPHeaderField: "x-client-locale")
        request.setValue("\(TimeZone.current.secondsFromGMT())", forHTTPHeaderField: "x-client-timezone-offset")
        request.setValue("https://platform.deepseek.com/usage", forHTTPHeaderField: "Referer")
        request.setValue(Self.deviceID, forHTTPHeaderField: "x-device-id")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("[debug] fetch \(path) error: \(error)")
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw DeepSeekError.businessError(code: -1, message: "DeepSeek 请求超时。")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.httpStatus(0)
        }
        debugLog("DeepSeek fetch \(path) status=\(http.statusCode) bytes=\(data.count)")

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw DeepSeekError.unauthorized
            }
            throw DeepSeekError.httpStatus(http.statusCode)
        }

        try DeepSeekResponseValidator.validateBusinessEnvelope(data)
        return try JSONDecoder().decode(APIEnvelope<Payload>.self, from: data)
    }

    private func waitForPlatformContext() async throws {
        loadUsagePageIfNeeded()
        debugLog("[debug] waitForPlatformContext url=\(webView.url?.absoluteString ?? "nil") isReady=\(isReady) isLoading=\(webView.isLoading)")
        for _ in 0..<40 {
            if isReady, !webView.isLoading {
                debugLog("[debug] platform context ready")
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        debugLog("[debug] platform context timeout url=\(webView.url?.absoluteString ?? "nil") isLoading=\(webView.isLoading)")
        throw DeepSeekError.businessError(code: -1, message: "正在等待 DeepSeek 登录会话同步。")
    }

    private func allowAuthorizationCaptureToSettle() async {
        for _ in 0..<40 {
            let token = ((try? await webView.evaluateJavaScript("window.__deepSeekUsageReadToken ? window.__deepSeekUsageReadToken() : ''")) as? String ?? "")
            if !token.isEmpty {
                debugLog("[debug] token captured, prefix=\(token.prefix(12)) len=\(token.count)")
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        debugLog("[debug] token capture timed out, url=\(webView.url?.absoluteString ?? "nil")")
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
          const token = (window.__deepSeekUsageReadToken && window.__deepSeekUsageReadToken()) || "";
          const headers = {
            "Accept": "application/json",
            "X-App-Version": "1.0.0",
            "x-client-platform": "web",
            "x-client-version": "1.0.0",
            "Referer": "https://platform.deepseek.com/usage"
          };
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
          const readStoredToken = () => {
            try {
              const raw = localStorage.getItem("userToken");
              if (!raw) return "";
              let t = raw;
              try {
                const p = JSON.parse(raw);
                if (typeof p === "string") t = p;
                else if (p && typeof p === "object") t = p.value || p.token || p.access_token || p.accessToken || p.userToken || "";
              } catch (_) {}
              t = String(t).trim().replace(/^["']|["']$/g, "");
              return (t.length >= 20 && !/\\s/.test(t)) ? t : "";
            } catch (_) {
              return "";
            }
          };
          window.__deepSeekUsageReadToken = () => {
            const captured = window.__deepSeekUsageAuthToken || "";
            if (/^Bearer\\s+/i.test(captured)) return captured.replace(/^Bearer\\s+/i, "").trim();
            return readStoredToken();
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
