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

    public static func hasUnclosedDynamicText(in token: String) -> Bool {
        var depth = 0

        for character in token {
            if character == "{" {
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
            }
        }

        return depth > 0
    }

    public static func match(
        currentToken: String,
        snippets: [Snippet]
    ) -> SnippetMatch? {
        return snippets
            .filter(\.isEnabled)
            .compactMap { snippet in
                match(for: currentToken, snippet: snippet)
            }
            .first
    }

    private static func match(for currentToken: String, snippet: Snippet) -> SnippetMatch? {
        let trigger = snippet.normalizedTrigger
        guard !trigger.isEmpty else {
            return nil
        }

        if currentToken == trigger {
            return SnippetMatch(snippet: snippet, matchedTextLength: currentToken.count)
        }

        guard currentToken.hasSuffix(trigger) else {
            return nil
        }

        let prefix = String(currentToken.dropLast(trigger.count))
        guard prefix.first == "{", prefix.last == "}" else {
            return nil
        }

        let addText = String(prefix.dropFirst().dropLast())
        return SnippetMatch(
            snippet: snippet,
            addText: addText,
            matchedTextLength: currentToken.count
        )
    }
}
