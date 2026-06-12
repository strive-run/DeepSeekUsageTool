import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var hostingController: NSHostingController<PopoverContentView>!
    private let appState: AppState
    private let cleanupBag = StatusBarCleanupBag()
    var onLoginRequested: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 318, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostingController = NSHostingController(
            rootView: PopoverContentView(
                appState: appState,
                onLoginRequested: { [weak self] in self?.onLoginRequested?() }
            )
        )
        self.panel.contentViewController = hostingController
        self.panel.backgroundColor = .clear
        self.panel.isOpaque = false
        self.panel.hasShadow = true
        self.panel.level = .statusBar
        self.panel.collectionBehavior = [.transient]
        self.panel.hidesOnDeactivate = false

        configureButton()
        installEventMonitor()
        installNotificationObservers()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconFactory.makeStatusImage()
        button.image?.isTemplate = true
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleStatusItemClick)
        button.target = self
        button.toolTip = "DeepSeek 用量"
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePanel()
            showStatusMenu()
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if panel.isVisible {
            closePanel()
        } else if let button = statusItem.button {
            showPanel(relativeTo: button)
            appState.refresh()
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func installEventMonitor() {
        cleanupBag.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func installNotificationObservers() {
        let notificationCenter = NotificationCenter.default
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        cleanupBag.notificationObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePanel()
                }
            }
        )

        cleanupBag.notificationObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePanel()
                }
            }
        )

        cleanupBag.notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePanel()
                }
            }
        )

        cleanupBag.notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePanel()
                }
            }
        )
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        let contentSize = fittingContentSize()
        panel.setContentSize(contentSize)

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        guard let buttonFrame = button.window?.convertToScreen(buttonFrameInWindow) else { return }
        let screen = button.window?.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let topGap: CGFloat = 6
        let horizontalInset: CGFloat = 8
        let proposedX = buttonFrame.midX - contentSize.width / 2
        let minX = screenFrame.minX + horizontalInset
        let maxX = screenFrame.maxX - contentSize.width - horizontalInset
        let originX = min(max(proposedX, minX), maxX)
        let originY = screenFrame.maxY - contentSize.height - topGap

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.orderFrontRegardless()
    }

    private func fittingContentSize() -> NSSize {
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        return NSSize(
            width: 318,
            height: max(320, ceil(fittingSize.height))
        )
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出应用", action: #selector(quitApplication), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            menu.popUp(positioning: quitItem, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

enum StatusIconFactory {
    static func makeStatusImage(size: CGFloat = 21) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocusFlipped(true)

        let inset = size * 0.01
        let bounds = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let path = DeepSeekLogoPath.makePath(in: bounds)
        NSColor.black.withAlphaComponent(1).setFill()
        NSGraphicsContext.current?.cgContext.addPath(path)
        NSGraphicsContext.current?.cgContext.fillPath()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

private final class StatusBarCleanupBag {
    var eventMonitor: Any?
    var notificationObservers: [NSObjectProtocol] = []

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
