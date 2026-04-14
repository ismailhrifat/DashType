#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

@main
struct DashTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPreferences.showsMenuBarExtraKey) private var showsMenuBarExtra = true

    @StateObject private var store: SnippetStore
    @StateObject private var permissions: PermissionManager
    @StateObject private var launchAtLogin: LaunchAtLoginManager
    @StateObject private var expansionController: TextExpansionController
    @StateObject private var snippetTransferController: SnippetTransferController
    @StateObject private var cloudSyncManager: CloudSyncManager

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
        _cloudSyncManager = StateObject(
            wrappedValue: CloudSyncManager(store: store)
        )
    }

    var body: some Scene {
        Window("", id: "dashboard") {
            DashboardView(
                store: store,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                expansionController: expansionController
            )
            .onAppear {
                expansionController.start()
                cloudSyncManager.activateIfNeeded()
            }
        }
        .defaultSize(width: 980, height: 660)

        MenuBarExtra("DashType", systemImage: "text.badge.plus", isInserted: $showsMenuBarExtra) {
            MenuBarContentView(
                store: store,
                permissions: permissions,
                launchAtLogin: launchAtLogin,
                expansionController: expansionController
            )
            .onAppear {
                permissions.refresh()
                expansionController.start()
                cloudSyncManager.activateIfNeeded()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                cloudSyncManager: cloudSyncManager,
                launchAtLogin: launchAtLogin,
                permissions: permissions,
                expansionController: expansionController,
                snippetTransferController: snippetTransferController
            )
            .onAppear {
                cloudSyncManager.activateIfNeeded()
            }
        }
        .defaultSize(width: 620, height: 500)
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
