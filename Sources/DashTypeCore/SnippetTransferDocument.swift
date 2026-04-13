import Foundation

public struct SnippetTransferDocument: Codable, Equatable, Sendable {
    public var folders: [SnippetTransferFolder]

    public init(folders: [SnippetTransferFolder]) {
        self.folders = folders
    }
}

public struct SnippetTransferFolder: Codable, Equatable, Sendable {
    public var name: String
    public var snippets: [SnippetTransferSnippet]

    public init(name: String, snippets: [SnippetTransferSnippet]) {
        self.name = name
        self.snippets = snippets
    }
}

public struct SnippetTransferSnippet: Codable, Equatable, Sendable {
    public var trigger: String
    public var title: String
    public var expandedText: String

    public init(trigger: String, title: String, expandedText: String) {
        self.trigger = trigger
        self.title = title
        self.expandedText = expandedText
    }

    private enum CodingKeys: String, CodingKey {
        case trigger
        case title
        case expandedText = "expanded_text"
    }
}
