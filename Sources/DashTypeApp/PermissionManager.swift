import ApplicationServices
import AppKit
import Combine
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityPollingTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted {
            accessibilityPollingTask?.cancel()
            accessibilityPollingTask = nil
        }
    }

    func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refresh()
        startAccessibilityPolling()
    }

    deinit {
        accessibilityPollingTask?.cancel()
    }

    private func startAccessibilityPolling() {
        accessibilityPollingTask?.cancel()
        accessibilityPollingTask = Task { [weak self] in
            for _ in 0..<180 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self?.refresh()
                }

                if await MainActor.run(body: { self?.accessibilityGranted == true }) {
                    return
                }
            }

            await MainActor.run {
                self?.accessibilityPollingTask = nil
            }
        }
    }
}
