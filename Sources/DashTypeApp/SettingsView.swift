import SwiftUI

struct SettingsView: View {
    @ObservedObject var cloudSyncManager: CloudSyncManager
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var expansionController: TextExpansionController
    @ObservedObject var snippetTransferController: SnippetTransferController

    @AppStorage(AppPreferences.showsMenuBarExtraKey) private var showsMenuBarExtra = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                preferencesCard
                transferCard
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 500)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: $cloudSyncManager.isPresentingAuthSheet) {
            CloudSyncAuthSheetView(cloudSyncManager: cloudSyncManager)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold))

                Text("Tune how DashType starts, appears, and behaves across your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statusBadge(
                title: expansionController.isMonitoring ? "Running" : "Paused",
                color: expansionController.isMonitoring ? .green : .orange
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            syncSettingsRow

            settingsToggle(
                title: "Open at Login",
                subtitle: "Launch DashType automatically when you sign in.",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            settingsToggle(
                title: "Show in the Menubar",
                subtitle: "Keep the quick-access menu available from the macOS menubar.",
                isOn: $showsMenuBarExtra
            )

            settingsToggle(
                title: "Turn Off DashType",
                subtitle: permissions.accessibilityGranted
                    ? "Stop listening for snippet triggers until you turn it back on."
                    : "Accessibility access is required before DashType can monitor your typing.",
                isOn: Binding(
                    get: { !expansionController.isMonitoring },
                    set: { expansionController.setMonitoringEnabled(!$0) }
                )
            )
            .disabled(!permissions.accessibilityGranted)

            if !permissions.accessibilityGranted {
                Button("Enable Accessibility") {
                    permissions.requestAccessibilityPrompt()
                }
                .buttonStyle(.borderedProminent)
            }

            if cloudSyncManager.isSyncing {
                Text("Syncing latest changes to Cloud...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let lastErrorMessage = launchAtLogin.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let syncErrorMessage = cloudSyncManager.syncErrorMessage {
                Text(syncErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var syncSettingsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Sync with Cloud")
                    .font(.headline)

                Text(cloudSyncManager.syncDescription.replacingOccurrences(of: "Firebase", with: "Cloud"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if cloudSyncManager.isAuthenticated {
                Button {
                    cloudSyncManager.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Sign Out")
                .padding(.top, 1)
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { cloudSyncManager.isSyncEnabled },
                    set: { cloudSyncManager.setSyncEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .padding(.top, 2)
        }
    }

    private var transferCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                actionButton(
                    title: "Import Snippets",
                    subtitle: "Bring folders in from a DashType JSON file.",
                    systemImage: "square.and.arrow.down"
                ) {
                    snippetTransferController.importFolders()
                }

                actionButton(
                    title: "Export Snippets",
                    subtitle: "Save selected folders to a JSON backup.",
                    systemImage: "square.and.arrow.up"
                ) {
                    snippetTransferController.exportFolders()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .padding(.top, 2)
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.13), in: Capsule())
    }
}
