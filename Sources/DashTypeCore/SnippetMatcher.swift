import Foundation

public enum SnippetMatcher {
    public static let tokenResetCharacters: Set<Character> = [
        " ",
        "\n",
        "\t",
        ".",
        ",",
        "!",
        "?",
        ":",
        ")",
        "]",
        "}",
    ]

    public static func match(
        currentToken: String,
        snippets: [Snippet]
    ) -> SnippetMatch? {
        return snippets
            .filter(\.isEnabled)
            .first(where: { $0.normalizedTrigger == currentToken })
            .map { SnippetMatch(snippet: $0) }
    }
}
