#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

@main
struct DashTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var store: SnippetStore
    @StateObject private var permissions: PermissionManager
    @StateObject private var launchAtLogin: LaunchAtLoginManager
    @StateObject private var expansionController: TextExpansionController
    @StateObject private var snippetTransferController: SnippetTransferController

    init() {
        let store = SnippetStore()
        let permissions = PermissionManager()
        _store = StateObject(wrappedValue: store)
        _permissions = StateObject(wrappedValue: permissions)
        _launchAtLogin = StateObject(wrappedValue: LaunchAtLoginManager())
        _expansionController = StateObject(
            wrappedValue: TextExpansionController(
                store: store,
                permissions: permissions
            )
        )
        _snippetTransferController = StateObject(
            wrappedValue: SnippetTransferController(store: store)
        )
    }

    var body: some Scene {
        Window("DashType", id: "dashboard") {
            DashboardView(
                store: store,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                expansionController: expansionController
            )
            .onAppear {
                expansionController.start()
            }
        }
        .defaultSize(width: 980, height: 660)

        MenuBarExtra("DashType", systemImage: "text.badge.plus") {
            MenuBarContentView(
                store: store,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                expansionController: expansionController
            )
            .onAppear {
                permissions.refresh()
                expansionController.start()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            DashboardView(
                store: store,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                expansionController: expansionController
            )
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import...") {
                    snippetTransferController.importFolders()
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])

                Button("Export...") {
                    snippetTransferController.exportFolders()
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
            }
        }
    }
}
