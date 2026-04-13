import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.configureOpenWindows()
            self?.refreshActivationPolicy()
        }
    }

    @objc private func handleWindowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        configure(window)
        refreshActivationPolicy()
    }

    private func configureOpenWindows() {
        NSApp.windows.forEach(configure)
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.configure(window)
            self?.refreshActivationPolicy()
        }
    }

    private func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }

    private func refreshActivationPolicy() {
        let hasVisibleDashboardWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !window.isMiniaturized
        }

        if hasVisibleDashboardWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
