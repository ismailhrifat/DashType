import Combine
import Foundation

@MainActor
public final class SnippetStore: ObservableObject {
    @Published public private(set) var folders: [SnippetFolder] = []
    @Published public var searchQuery = ""

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

            self.fileURL = applicationSupport
                .appendingPathComponent("DashType", isDirectory: true)
                .appendingPathComponent("snippets.json")
        }

        load()
    }

    public var filteredFolders: [SnippetFolder] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return folders.compactMap { folder in
            let sortedSnippets = folder.snippets.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }

            guard !query.isEmpty else {
                var visibleFolder = folder
                visibleFolder.snippets = sortedSnippets
                return visibleFolder
            }

            let filteredSnippets = sortedSnippets.filter { snippet in
                snippet.title.localizedCaseInsensitiveContains(query)
                    || snippet.trigger.localizedCaseInsensitiveContains(query)
                    || snippet.content.localizedCaseInsensitiveContains(query)
            }

            let folderMatches = folder.name.localizedCaseInsensitiveContains(query)
            guard folderMatches || !filteredSnippets.isEmpty else {
                return nil
            }

            var visibleFolder = folder
            visibleFolder.snippets = folderMatches ? sortedSnippets : filteredSnippets
            return visibleFolder
        }
    }

    public var enabledSnippets: [Snippet] {
        folders
            .filter(\.isEnabled)
            .flatMap(\.snippets)
            .filter(\.isEnabled)
    }

    public func snippet(id: Snippet.ID?) -> Snippet? {
        guard let id else {
            return nil
        }

        return folders
            .flatMap(\.snippets)
            .first(where: { $0.id == id })
    }

    public func folder(id: SnippetFolder.ID?) -> SnippetFolder? {
        guard let id else {
            return nil
        }

        return folders.first(where: { $0.id == id })
    }

    public var firstSnippetID: Snippet.ID? {
        filteredFolders
            .flatMap(\.snippets)
            .first?
            .id
    }

    @discardableResult
    public func createFolder() -> SnippetFolder {
        let now = Date()
        let folder = SnippetFolder(
            name: "Folder \(folders.count + 1)",
            snippets: [],
            createdAt: now,
            updatedAt: now
        )

        folders.append(folder)
        persist()
        return folder
    }

    @discardableResult
    public func createSnippet(in folderID: SnippetFolder.ID) -> Snippet? {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return nil
        }

        let snippetCount = folders.flatMap(\.snippets).count + 1
        let now = Date()
        let snippet = Snippet(
            title: "Snippet \(snippetCount)",
            trigger: "/snippet-\(snippetCount)",
            content: "",
            isEnabled: true,
            createdAt: now,
            updatedAt: now
        )

        folders[index].snippets.append(snippet)
        folders[index].updatedAt = now
        persist()
        return snippet
    }

    public func toggleFolder(_ id: SnippetFolder.ID, isEnabled: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        folders[index].isEnabled = isEnabled
        folders[index].updatedAt = Date()
        persist()
    }

    public func renameFolder(_ id: SnippetFolder.ID, name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        folders[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[index].updatedAt = Date()
        persist()
    }

    public func deleteFolder(_ id: SnippetFolder.ID) {
        folders.removeAll(where: { $0.id == id })
        persist()
    }

    @discardableResult
    public func updateSnippet(
        id: Snippet.ID,
        title: String,
        trigger: String,
        content: String,
        richTextData: Data? = nil,
        isEnabled: Bool
    ) -> Bool {
        guard let location = snippetLocation(id: id) else {
            return false
        }

        let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if conflictingSnippet(for: normalizedTrigger, excluding: id) != nil {
            return false
        }

        let now = Date()
        folders[location.folderIndex].snippets[location.snippetIndex].title = title
        folders[location.folderIndex].snippets[location.snippetIndex].trigger = normalizedTrigger
        folders[location.folderIndex].snippets[location.snippetIndex].content = content
        folders[location.folderIndex].snippets[location.snippetIndex].richTextData = richTextData
        folders[location.folderIndex].snippets[location.snippetIndex].isEnabled = isEnabled
        folders[location.folderIndex].snippets[location.snippetIndex].updatedAt = now
        folders[location.folderIndex].updatedAt = now
        persist()
        return true
    }

    public func toggleSnippet(_ id: Snippet.ID, isEnabled: Bool) {
        guard let location = snippetLocation(id: id) else {
            return
        }

        let now = Date()
        folders[location.folderIndex].snippets[location.snippetIndex].isEnabled = isEnabled
        folders[location.folderIndex].snippets[location.snippetIndex].updatedAt = now
        folders[location.folderIndex].updatedAt = now
        persist()
    }

    public func deleteSnippet(_ id: Snippet.ID) {
        guard let location = snippetLocation(id: id) else {
            return
        }

        folders[location.folderIndex].snippets.remove(at: location.snippetIndex)
        folders[location.folderIndex].updatedAt = .now
        persist()
    }

    public func replaceAll(with folders: [SnippetFolder]) {
        self.folders = folders
        persist()
    }

    public func appendFolders(_ folders: [SnippetFolder]) {
        self.folders.append(contentsOf: folders)
        persist()
    }

    public func conflictingSnippet(for trigger: String, excluding id: Snippet.ID? = nil) -> Snippet? {
        let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTrigger.isEmpty else {
            return nil
        }

        return folders
            .flatMap(\.snippets)
            .first { snippet in
                let existingTrigger = snippet.normalizedTrigger
                guard snippet.id != id, !existingTrigger.isEmpty else {
                    return false
                }

                return existingTrigger == normalizedTrigger
                    || existingTrigger.hasPrefix(normalizedTrigger)
                    || normalizedTrigger.hasPrefix(existingTrigger)
            }
    }

    public func exportDocument(for folderIDs: [SnippetFolder.ID]) -> SnippetTransferDocument {
        let selectedIDs = Set(folderIDs)
        let exportedFolders = folders
            .filter { selectedIDs.contains($0.id) }
            .map { folder in
                SnippetTransferFolder(
                    name: folder.normalizedName.isEmpty ? "Untitled Folder" : folder.normalizedName,
                    snippets: folder.snippets.map { snippet in
                        SnippetTransferSnippet(
                            trigger: snippet.trigger,
                            title: snippet.title,
                            expandedText: snippet.content
                        )
                    }
                )
            }

        return SnippetTransferDocument(folders: exportedFolders)
    }

    @discardableResult
    public func importFolders(from transferFolders: [SnippetTransferFolder]) -> [SnippetFolder] {
        let now = Date()
        let importedFolders = transferFolders.map { folder in
            let proposedName = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = uniqueFolderName(for: proposedName.isEmpty ? "Imported Folder" : proposedName)

            return SnippetFolder(
                name: finalName,
                isEnabled: true,
                snippets: folder.snippets.map { snippet in
                    Snippet(
                        title: snippet.title,
                        trigger: snippet.trigger,
                        content: snippet.expandedText,
                        isEnabled: true,
                        createdAt: now,
                        updatedAt: now
                    )
                },
                createdAt: now,
                updatedAt: now
            )
        }

        folders.append(contentsOf: importedFolders)
        persist()
        return importedFolders
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            folders = try decodeFolders(from: data)
            if folders.isEmpty {
                folders = [SnippetFolder.bootstrap()]
                persist()
            }
        } catch {
            folders = [SnippetFolder.bootstrap()]
            persist()
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(folders)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist snippets: \(error)")
        }
    }

    private func decodeFolders(from data: Data) throws -> [SnippetFolder] {
        if let folders = try? decoder.decode([SnippetFolder].self, from: data) {
            return folders
        }

        if let snippets = try? decoder.decode([Snippet].self, from: data) {
            return [SnippetFolder.bootstrap(snippets: snippets.isEmpty ? [Snippet.sample] : snippets)]
        }

        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Unsupported snippet store format")
        )
    }

    private func snippetLocation(id: Snippet.ID) -> (folderIndex: Int, snippetIndex: Int)? {
        for (folderIndex, folder) in folders.enumerated() {
            if let snippetIndex = folder.snippets.firstIndex(where: { $0.id == id }) {
                return (folderIndex, snippetIndex)
            }
        }

        return nil
    }

    private func uniqueFolderName(for proposedName: String) -> String {
        let existingNames = Set(folders.map(\.normalizedName))
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
