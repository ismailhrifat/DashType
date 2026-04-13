import AppKit
#if canImport(DashTypeCore)
import DashTypeCore
#endif
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SnippetTransferController: ObservableObject {
    private let store: SnippetStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: SnippetStore) {
        self.store = store
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func exportFolders() {
        guard !store.folders.isEmpty else {
            presentInfoAlert(
                title: "Nothing to Export",
                message: "Create at least one folder before exporting."
            )
            return
        }

        let selections = presentFolderSelection(
            title: "Export Folders",
            message: "Choose which folders to export as JSON.",
            folderNames: store.folders.map { folder in
                folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName
            },
            confirmTitle: "Export"
        )

        guard let selections, !selections.isEmpty else {
            return
        }

        let document = SnippetTransferDocument(
            folders: selections.map { folderIndex in
                let folder = store.folders[folderIndex]
                return SnippetTransferFolder(
                    name: folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName,
                    snippets: folder.snippets.map { snippet in
                        SnippetTransferSnippet(
                            trigger: snippet.trigger,
                            title: snippet.title,
                            expandedText: RichTextMarkdownCodec.htmlString(from: snippet)
                        )
                    }
                )
            }
        )

        do {
            let data = try encoder.encode(document)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "DashType Export.json"

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }

            try data.write(to: url, options: [.atomic])
        } catch {
            presentErrorAlert(
                title: "Export Failed",
                message: "DashType could not write the selected folders to JSON.",
                error: error
            )
        }
    }

    func importFolders() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let document = try decoder.decode(SnippetTransferDocument.self, from: data)

            guard !document.folders.isEmpty else {
                presentInfoAlert(
                    title: "No Folders Found",
                    message: "The selected JSON file does not contain any folders to import."
                )
                return
            }

            let selections = presentFolderSelection(
                title: "Import Folders",
                message: "Choose which folders from the JSON file to import.",
                folderNames: document.folders.map(\.name),
                confirmTitle: "Import"
            )

            guard let selections, !selections.isEmpty else {
                return
            }

            let selectedFolders = selections.map { document.folders[$0] }
            let now = Date()
            let importedFolders = selectedFolders.map { folder in
                SnippetFolder(
                    name: folder.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    isEnabled: true,
                    snippets: folder.snippets.map { snippet in
                        let attributed = RichTextMarkdownCodec.attributedString(fromTransferMarkup: snippet.expandedText)
                        return Snippet(
                            title: snippet.title,
                            trigger: snippet.trigger,
                            content: attributed.string,
                            richTextData: RichTextMarkdownCodec.rtfData(from: attributed),
                            isEnabled: true,
                            createdAt: now,
                            updatedAt: now
                        )
                    },
                    createdAt: now,
                    updatedAt: now
                )
            }

            store.appendFolders(importedFolders.map { folder in
                let baseName = folder.normalizedName.isEmpty ? "Imported Folder" : folder.normalizedName
                var finalFolder = folder
                finalFolder.name = uniqueImportedFolderName(baseName)
                return finalFolder
            })
        } catch {
            presentErrorAlert(
                title: "Import Failed",
                message: "DashType could not read that JSON file.",
                error: error
            )
        }
    }

    private func presentFolderSelection(
        title: String,
        message: String,
        folderNames: [String],
        confirmTitle: String
    ) -> [Int]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")

        let checkboxes = folderNames.map { name in
            let button = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            button.state = .on
            button.lineBreakMode = .byTruncatingMiddle
            return button
        }

        let stackView = NSStackView(views: checkboxes)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = folderNames.count > 5
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = stackView
        scrollView.frame = NSRect(x: 0, y: 0, width: 360, height: min(CGFloat(max(folderNames.count, 1)) * 26, 220))

        alert.accessoryView = scrollView

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return checkboxes.enumerated()
            .compactMap { index, checkbox in
                checkbox.state == .on ? index : nil
            }
    }

    private func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentErrorAlert(title: String, message: String, error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func uniqueImportedFolderName(_ proposedName: String) -> String {
        let existingNames = Set(store.folders.map(\.normalizedName))
        guard existingNames.contains(proposedName) else {
            return proposedName
        }

        var suffix = 2
        while existingNames.contains("\(proposedName) \(suffix)") {
            suffix += 1
        }

        return "\(proposedName) \(suffix)"
    }
}
