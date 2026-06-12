import AppKit
import WebKit

@MainActor
protocol LoginWindowControllerDelegate: AnyObject {
    func loginWindowController(_ controller: LoginWindowController, didLoginWith snapshot: UsageSnapshot)
    func loginWindowControllerDidCancel(_ controller: LoginWindowController)
}

@MainActor
final class LoginWindowController: NSWindowController, WKNavigationDelegate {
    weak var loginDelegate: LoginWindowControllerDelegate?

    private let webSession: DeepSeekWebSession
    private let webView: WKWebView
    private var isValidatingLogin = false
    private var hasCompletedLogin = false

    init(webSession: DeepSeekWebSession) {
        self.webSession = webSession
        self.webView = webSession.webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 DeepSeek"
        window.center()
        window.contentView = webView

        super.init(window: window)
        webView.navigationDelegate = self
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginLogin() {
        hasCompletedLogin = false
        isValidatingLogin = false
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webSession.loadUsagePageIfNeeded()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host?.hasSuffix("platform.deepseek.com") == true else { return }
        guard !hasCompletedLogin, !isValidatingLogin else { return }
        Task { await validateLoginSession() }
    }

    private func validateLoginSession() async {
        isValidatingLogin = true
        defer { isValidatingLogin = false }

        do {
            let snapshot = try await webSession.fetchSnapshot()
            hasCompletedLogin = true
            loginDelegate?.loginWindowController(self, didLoginWith: snapshot)
            close()
        } catch {
            return
        }
    }
}

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !hasCompletedLogin else { return }
        loginDelegate?.loginWindowControllerDidCancel(self)
    }
}
