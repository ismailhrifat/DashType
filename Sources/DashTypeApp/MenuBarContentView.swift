import AppKit
#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var expansionController: TextExpansionController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DashType")
                        .font(.headline)
                    Text("\(store.enabledSnippets.count) active snippets")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(expansionController.isMonitoring ? "Running" : "Stopped")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(expansionController.isMonitoring ? .green : .red)
                Circle()
                    .fill(expansionController.isMonitoring ? .green : .red)
                    .frame(width: 10, height: 10)
            }

            Divider()

            Toggle(
                "Open at Login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            if !permissions.accessibilityGranted {
                Button("Enable Accessibility") {
                    permissions.requestAccessibilityPrompt()
                }
            }

            Toggle(
                "Turn Off",
                isOn: Binding(
                    get: { !expansionController.isMonitoring },
                    set: { expansionController.setMonitoringEnabled(!$0) }
                )
            )
            .disabled(!permissions.accessibilityGranted)

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openDashboard()
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.bordered)
                .help("Quit DashType")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func openDashboard() {
        openWindow(id: "dashboard")

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            if let dashboardWindow = NSApp.windows.first(where: {
                $0.styleMask.contains(.titled) && !$0.isMiniaturized
            }) {
                dashboardWindow.makeKeyAndOrderFront(nil)
                dashboardWindow.orderFrontRegardless()
            }
        }
    }
}
