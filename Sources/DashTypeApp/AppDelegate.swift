import AppKit
import FirebaseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasActivatedOnInitialLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FirebaseApp.configure()

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.configureOpenWindows()
            self?.refreshActivationPolicy()
            self?.activateOnInitialLaunchIfNeeded()
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

    @objc private func handleUserDefaultsDidChange(_ notification: Notification) {
        refreshActivationPolicy()
    }

    private func configure(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }

    private func activateOnInitialLaunchIfNeeded() {
        guard !hasActivatedOnInitialLaunch else {
            return
        }

        let hasVisibleDashboardWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !window.isMiniaturized
        }

        guard hasVisibleDashboardWindow else {
            return
        }

        hasActivatedOnInitialLaunch = true
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshActivationPolicy() {
        let hasVisibleDashboardWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !window.isMiniaturized
        }

        let showsMenuBarExtra = UserDefaults.standard.object(forKey: AppPreferences.showsMenuBarExtraKey) as? Bool ?? true

        let desiredPolicy: NSApplication.ActivationPolicy
        if hasVisibleDashboardWindow {
            desiredPolicy = .regular
        } else if showsMenuBarExtra {
            desiredPolicy = .accessory
        } else {
            desiredPolicy = .regular
        }

        if NSApp.activationPolicy() != desiredPolicy {
            NSApp.setActivationPolicy(desiredPolicy)
        }
    }
}
