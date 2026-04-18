#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var expansionController: TextExpansionController

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedSnippetID: Snippet.ID?
    @State private var expandedFolderIDs: Set<SnippetFolder.ID> = []
    @State private var editingFolderID: SnippetFolder.ID?
    @State private var folderNameDraft = ""
    @State private var folderPendingDeletion: SnippetFolder?
    @FocusState private var focusedFolderID: SnippetFolder.ID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        .frame(minWidth: 920, idealWidth: 1050, minHeight: 580, idealHeight: 660)
        .onAppear {
            permissions.refresh()
            expansionController.start()

            if selectedSnippetID == nil {
                selectedSnippetID = store.firstSnippetID
            }
        }
        .onChange(of: visibleSnippetIDs) { _, ids in
            if !ids.contains(selectedSnippetID ?? UUID()) {
                selectedSnippetID = ids.first
            }
        }
        .onChange(of: store.filteredFolders.map(\.id)) { _, ids in
            if isSearching {
                expandedFolderIDs.formUnion(ids)
            }
        }
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        folderPendingDeletion = nil
                    }
                }
            ),
            presenting: folderPendingDeletion
        ) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteFolder(folder.id)
            }
        } message: { folder in
            let name = folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName
            Text("This will permanently delete the folder \"\(name)\" and all snippets inside it.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DashType")
                        .font(.system(size: 28, weight: .bold))
                    Text("Fast text expansion from your menu bar.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search snippets", text: $store.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            if !permissions.accessibilityGranted {
                accessibilityCard
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.filteredFolders.isEmpty {
                        emptyFoldersState
                    } else {
                        ForEach(store.filteredFolders) { folder in
                            folderSection(folder)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                let folder = store.createFolder()
                expandedFolderIDs.insert(folder.id)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Accessibility Needed", systemImage: "hand.raised.fill")
                .foregroundStyle(.orange)

            Text("Enable Accessibility in System Settings so DashType can expand snippets anywhere you type.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Enable Accessibility") {
                permissions.requestAccessibilityPrompt()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyFoldersState: some View {
        ContentUnavailableView(
            "No Folders Yet",
            systemImage: "folder",
            description: Text("Create a folder to start organizing your snippets.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func folderSection(_ folder: SnippetFolder) -> some View {
        let isExpanded = folderIsExpanded(folder.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    toggleFolder(folder.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)

                        if editingFolderID == folder.id {
                            TextField("Folder name", text: $folderNameDraft)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedFolderID, equals: folder.id)
                                .onSubmit {
                                    commitFolderRename(folder.id)
                                }
                        } else {
                            Text(folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(folder.isEnabled ? "Disable Folder" : "Enable Folder") {
                        store.toggleFolder(folder.id, isEnabled: !folder.isEnabled)
                    }

                    Button("Rename Folder") {
                        startRenamingFolder(folder)
                    }

                    Divider()

                    Text(folderStatusText(folder))

                    Divider()

                    Button("Delete Folder", role: .destructive) {
                        folderPendingDeletion = folder
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if let snippet = store.createSnippet(in: folder.id) {
                            selectedSnippetID = snippet.id
                        }
                    } label: {
                        Label("New Snippet", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)

                    if folder.snippets.isEmpty {
                        Text("This folder is empty.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    } else {
                        ForEach(folder.snippets) { snippet in
                            snippetRow(snippet, folderIsEnabled: folder.isEnabled)
                        }
                    }
                }
                .padding(.leading, 26)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var detail: some View {
        Group {
            if let snippet = store.snippet(id: selectedSnippetID) {
                SnippetEditorView(
                    snippet: snippet,
                    sidebarIsVisible: columnVisibility != .detailOnly,
                    onSave: { id, title, trigger, content, richTextData, isEnabled in
                        store.updateSnippet(
                            id: id,
                            title: title,
                            trigger: trigger,
                            content: content,
                            richTextData: richTextData,
                            isEnabled: isEnabled
                        )
                    },
                    onDelete: { id in
                        store.deleteSnippet(id)
                        selectedSnippetID = store.firstSnippetID
                    },
                    duplicateTriggerOwnerTitle: { id, trigger in
                        let conflictingSnippet = store.conflictingSnippet(for: trigger, excluding: id)
                        return conflictingSnippet?.normalizedTitle.isEmpty == false
                            ? conflictingSnippet?.normalizedTitle
                            : conflictingSnippet?.title
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Snippet",
                    systemImage: "text.badge.plus",
                    description: Text("Create a folder, then add a snippet inside it.")
                )
            }
        }
    }

    private func snippetRow(_ snippet: Snippet, folderIsEnabled: Bool) -> some View {
        let isSelected = selectedSnippetID == snippet.id
        let showsEnabledState = folderIsEnabled && snippet.isEnabled

        return Button {
            selectedSnippetID = snippet.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snippet.trigger)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(snippet.normalizedTitle.isEmpty ? "Untitled" : snippet.normalizedTitle)
                        .lineLimit(1)
                        .foregroundStyle(Color.secondary)
                        .font(.subheadline)
                }

                Spacer()

                Circle()
                    .fill(showsEnabledState ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(snippetRowBackground(snippet))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.9) : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func snippetRowBackground(_ snippet: Snippet) -> some ShapeStyle {
        return AnyShapeStyle(Color.primary.opacity(0.05))
    }

    private func folderIsExpanded(_ id: SnippetFolder.ID) -> Bool {
        isSearching || expandedFolderIDs.contains(id)
    }

    private func toggleFolder(_ id: SnippetFolder.ID) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if expandedFolderIDs.contains(id) {
                expandedFolderIDs.remove(id)
            } else {
                expandedFolderIDs.insert(id)
            }
        }
    }

    private func deleteFolder(_ id: SnippetFolder.ID) {
        store.deleteFolder(id)
        expandedFolderIDs.remove(id)
        if editingFolderID == id {
            cancelFolderRename()
        }
        selectedSnippetID = store.firstSnippetID
    }

    private func folderStatusText(_ folder: SnippetFolder) -> String {
        folder.snippets.count == 1 ? "1 snippet" : "\(folder.snippets.count) snippets"
    }

    private func startRenamingFolder(_ folder: SnippetFolder) {
        editingFolderID = folder.id
        folderNameDraft = folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName
        focusedFolderID = folder.id
    }

    private func commitFolderRename(_ id: SnippetFolder.ID) {
        let trimmedName = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.renameFolder(id, name: trimmedName.isEmpty ? "Untitled Folder" : trimmedName)
        editingFolderID = nil
        folderNameDraft = ""
        focusedFolderID = nil
    }

    private func cancelFolderRename() {
        editingFolderID = nil
        folderNameDraft = ""
        focusedFolderID = nil
    }

    private var visibleSnippetIDs: [Snippet.ID] {
        store.filteredFolders
            .flatMap(\.snippets)
            .map(\.id)
    }

    private var isSearching: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
