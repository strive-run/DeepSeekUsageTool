import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, LoginWindowControllerDelegate {
    private let webSession: DeepSeekWebSession
    private let appState: AppState
    private var statusBarController: StatusBarController?
    private var loginWindowController: LoginWindowController?

    override init() {
        let webSession = DeepSeekWebSession()
        self.webSession = webSession
        self.appState = AppState(webSession: webSession)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = StatusBarController(appState: appState)
        controller.onLoginRequested = { [weak self] in
            self?.showLogin()
        }
        statusBarController = controller

        webSession.loadUsagePageIfNeeded()
        appState.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.cancelRefresh()
    }

    func showLogin() {
        let controller = loginWindowController ?? LoginWindowController(webSession: webSession)
        controller.loginDelegate = self
        loginWindowController = controller
        controller.beginLogin()
    }

    func loginWindowController(_ controller: LoginWindowController, didLoginWith snapshot: UsageSnapshot) {
        appState.update(with: snapshot)
        loginWindowController = nil
    }

    func loginWindowControllerDidCancel(_ controller: LoginWindowController) {
        loginWindowController = nil
    }
}

@main
enum DeepSeekUsageMain {
    @MainActor
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        Self.delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}
