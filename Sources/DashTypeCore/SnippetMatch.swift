import Foundation

public struct SnippetMatch: Equatable, Sendable {
    public let snippet: Snippet
    public let addText: String
    public let matchedTextLength: Int

    public init(snippet: Snippet, addText: String = "", matchedTextLength: Int? = nil) {
        self.snippet = snippet
        self.addText = addText
        self.matchedTextLength = matchedTextLength ?? snippet.normalizedTrigger.count
    }

    public var replacementText: String {
        snippet.content
    }

    public var charactersToReplace: Int {
        matchedTextLength
    }
}

public struct ProcessedSnippetCommands: Equatable, Sendable {
    public let text: String
    public let cursorLocation: Int?
    public let cursorLocationUTF16: Int?

    public init(text: String, cursorLocation: Int?, cursorLocationUTF16: Int?) {
        self.text = text
        self.cursorLocation = cursorLocation
        self.cursorLocationUTF16 = cursorLocationUTF16
    }

    public var cursorMoveLeftCount: Int {
        guard let cursorLocationUTF16 else {
            return 0
        }

        return max((text as NSString).length - cursorLocationUTF16, 0)
    }
}

public enum SnippetCommandProcessor {
    public static let cursorToken = "{cursor}"
    public static let clipboardToken = "{clipboard}"
    public static let addTextToken = "{addtext}"

    public static func process(_ text: String) -> ProcessedSnippetCommands {
        guard !text.isEmpty else {
            return ProcessedSnippetCommands(text: "", cursorLocation: nil, cursorLocationUTF16: nil)
        }

        var processedText = ""
        var cursorLocation: Int?
        var cursorLocationUTF16: Int?
        var searchStart = text.startIndex

        while let range = text[searchStart...].range(of: cursorToken) {
            processedText += text[searchStart..<range.lowerBound]

            if cursorLocation == nil {
                cursorLocation = processedText.count
                cursorLocationUTF16 = (processedText as NSString).length
            }

            searchStart = range.upperBound
        }

        processedText += text[searchStart...]
        return ProcessedSnippetCommands(
            text: processedText,
            cursorLocation: cursorLocation,
            cursorLocationUTF16: cursorLocationUTF16
        )
    }
}
