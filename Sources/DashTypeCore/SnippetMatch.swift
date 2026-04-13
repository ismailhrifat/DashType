import Foundation

public struct SnippetMatch: Equatable, Sendable {
    public let snippet: Snippet

    public init(snippet: Snippet) {
        self.snippet = snippet
    }

    public var replacementText: String {
        snippet.content
    }

    public var charactersToReplace: Int {
        snippet.normalizedTrigger.count
    }
}
