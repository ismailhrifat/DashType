import AppKit
#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

@MainActor
enum RichTextMarkdownCodec {
    static func attributedString(from snippet: Snippet) -> NSAttributedString {
        if let richTextData = snippet.richTextData,
           let attributed = try? NSAttributedString(
               data: richTextData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return normalizeBaseFont(in: attributed)
        }

        return NSAttributedString(
            string: snippet.content,
            attributes: baseBodyAttributes()
        )
    }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let html = htmlDocument(fromMarkdown: markdown)
        return attributedString(fromHTML: html, fallback: markdown)
    }

    static func attributedString(fromHTML html: String) -> NSAttributedString {
        attributedString(fromHTML: html, fallback: html)
    }

    static func attributedString(fromTransferMarkup markup: String) -> NSAttributedString {
        if looksLikeHTML(markup) {
            return attributedString(fromHTML: markup)
        }

        return attributedString(fromMarkdown: markup)
    }

    static func htmlString(from snippet: Snippet) -> String {
        htmlString(from: attributedString(from: snippet))
    }

    static func htmlString(from attributedString: NSAttributedString) -> String {
        guard let data = htmlData(from: attributedString),
              let html = String(data: data, encoding: .utf8) else {
            return """
            <html>
            <body><p>\(escapeHTMLPreservingLineBreaks(attributedString.string))</p></body>
            </html>
            """
        }

        return html
    }

    private static func attributedString(fromHTML html: String, fallback: String) -> NSAttributedString {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              ) else {
            return NSAttributedString(string: fallback, attributes: baseBodyAttributes())
        }

        return normalizeBaseFont(in: attributed)
    }

    static func markdown(from snippet: Snippet) -> String {
        markdown(from: attributedString(from: snippet))
    }

    static func markdown(from attributedString: NSAttributedString) -> String {
        let text = attributedString.string as NSString
        guard text.length > 0 else {
            return ""
        }

        var markdownBlocks: [String] = []
        var index = 0

        while index < text.length {
            let paragraphRange = text.paragraphRange(for: NSRange(location: index, length: 0))
            var paragraphText = text.substring(with: paragraphRange)
            if paragraphText.hasSuffix("\n") {
                paragraphText.removeLast()
            }

            let trimmed = paragraphText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                markdownBlocks.append("")
                index = NSMaxRange(paragraphRange)
                continue
            }

            let inlineRange = NSRange(location: paragraphRange.location, length: max(paragraphRange.length - 1, 0))
            let inlineMarkdown = serializeInlineMarkdown(
                in: attributedString,
                range: inlineRange,
                fallback: paragraphText
            )

            if let listMarkdown = markdownListLine(
                from: paragraphText,
                inlineMarkdown: inlineMarkdown
            ) {
                markdownBlocks.append(listMarkdown)
                index = NSMaxRange(paragraphRange)
                continue
            }

            let headingPrefix = markdownHeadingPrefix(for: attributedString, range: inlineRange)
            if headingPrefix.isEmpty {
                markdownBlocks.append(inlineMarkdown)
            } else {
                markdownBlocks.append("\(headingPrefix) \(inlineMarkdown)")
            }

            index = NSMaxRange(paragraphRange)
        }

        return markdownBlocks.joined(separator: "\n")
    }

    static func rtfData(from attributedString: NSAttributedString) -> Data? {
        try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func htmlData(from attributedString: NSAttributedString) -> Data? {
        try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
    }

    private static func baseBodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private static func normalizeBaseFont(in attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.beginEditing()
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let currentFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let size = max(currentFont.pointSize, 14)
            let traits = NSFontManager.shared.traits(of: currentFont)
            let weight: NSFont.Weight = traits.contains(.boldFontMask) ? .semibold : .regular
            let italic = traits.contains(.italicFontMask)
            let font = fontWith(size: size, weight: weight, italic: italic)
            mutable.addAttribute(.font, value: font, range: range)
        }
        mutable.endEditing()
        return mutable
    }

    static func fontWith(size: CGFloat, weight: NSFont.Weight, italic: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else {
            return base
        }

        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private static func markdownHeadingPrefix(for attributedString: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else {
            return ""
        }

        let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let size = font?.pointSize ?? 14

        switch size {
        case 26...:
            return "#"
        case 20..<26:
            return "##"
        case 16..<20:
            return "###"
        default:
            return ""
        }
    }

    private static func serializeInlineMarkdown(
        in attributedString: NSAttributedString,
        range: NSRange,
        fallback: String
    ) -> String {
        guard range.length > 0 else {
            return fallback
        }

        let nsText = attributedString.string as NSString
        var pieces: [String] = []
        attributedString.enumerateAttributes(in: range) { attributes, subrange, _ in
            let substring = nsText.substring(with: subrange)
            var chunk = escapeMarkdown(substring)

            if let link = attributes[.link] {
                let url = String(describing: link)
                chunk = "[\(chunk)](\(url))"
            }

            if let baselineOffset = attributes[.baselineOffset] as? NSNumber {
                if baselineOffset.doubleValue > 0 {
                    chunk = "<sup>\(chunk)</sup>"
                } else if baselineOffset.doubleValue < 0 {
                    chunk = "<sub>\(chunk)</sub>"
                }
            }

            if let underline = attributes[.underlineStyle] as? NSNumber,
               underline.intValue != 0 {
                chunk = "<u>\(chunk)</u>"
            }

            if let strike = attributes[.strikethroughStyle] as? NSNumber,
               strike.intValue != 0 {
                chunk = "~~\(chunk)~~"
            }

            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.italicFontMask) {
                    chunk = "*\(chunk)*"
                }
                if traits.contains(.boldFontMask) && font.pointSize < 16 {
                    chunk = "**\(chunk)**"
                }
            }

            pieces.append(chunk)
        }

        return pieces.joined()
    }

    private static func escapeMarkdown(_ string: String) -> String {
        var escaped = string
        let replacements = [
            ("\\", "\\\\"),
            ("[", "\\["),
            ("]", "\\]"),
            ("(", "\\("),
            (")", "\\)"),
        ]

        for (source, target) in replacements {
            escaped = escaped.replacingOccurrences(of: source, with: target)
        }

        return escaped
    }

    private static func htmlDocument(fromMarkdown markdown: String) -> String {
        let allowedTagPlaceholders = [
            "<u>": "__DASHTYPE_U_OPEN__",
            "</u>": "__DASHTYPE_U_CLOSE__",
            "<sub>": "__DASHTYPE_SUB_OPEN__",
            "</sub>": "__DASHTYPE_SUB_CLOSE__",
            "<sup>": "__DASHTYPE_SUP_OPEN__",
            "</sup>": "__DASHTYPE_SUP_CLOSE__",
        ]

        var sanitized = markdown
        for (tag, placeholder) in allowedTagPlaceholders {
            sanitized = sanitized.replacingOccurrences(of: tag, with: placeholder)
        }

        sanitized = escapeHTML(sanitized)

        for (tag, placeholder) in allowedTagPlaceholders {
            sanitized = sanitized.replacingOccurrences(of: placeholder, with: tag)
        }

        let lines = sanitized.components(separatedBy: "\n")
        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let detectedListType = listType(for: trimmed) {
                var listItems: [String] = []
                while index < lines.count {
                    let currentTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let currentType = listType(for: currentTrimmed), currentType == detectedListType else {
                        break
                    }

                    listItems.append("<li>\(inlineHTML(from: removeListMarker(from: currentTrimmed)))</li>")
                    index += 1
                }

                let tag = detectedListType == .unordered ? "ul" : "ol"
                blocks.append("<\(tag)>\(listItems.joined())</\(tag)>")
                continue
            }

            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                let (tag, text) = headingTagAndText(from: trimmed)
                blocks.append("<\(tag)>\(inlineHTML(from: text))</\(tag)>")
                index += 1
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || listType(for: nextTrimmed) != nil || nextTrimmed.hasPrefix("#") {
                    break
                }
                paragraphLines.append(nextTrimmed)
                index += 1
            }

            blocks.append("<p>\(inlineHTML(from: paragraphLines.joined(separator: "<br/>")))</p>")
        }

        return """
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system; font-size: 14px; color: #111111; }
        h1 { font-size: 28px; font-weight: 700; }
        h2 { font-size: 22px; font-weight: 700; }
        h3 { font-size: 18px; font-weight: 700; }
        p { margin: 0 0 10px 0; }
        ul, ol { margin: 0 0 10px 22px; }
        </style>
        </head>
        <body>\(blocks.joined(separator: "\n"))</body>
        </html>
        """
    }

    private static func inlineHTML(from string: String) -> String {
        var html = string
        html = replaceRegex(#"\[(.+?)\]\((.+?)\)"#, in: html) { match in
            "<a href=\"\(match[2])\">\(match[1])</a>"
        }
        html = replaceRegex(#"\*\*(.+?)\*\*"#, in: html) { match in
            "<strong>\(match[1])</strong>"
        }
        html = replaceRegex(#"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)"#, in: html) { match in
            "<em>\(match[1])</em>"
        }
        html = replaceRegex(#"~~(.+?)~~"#, in: html) { match in
            "<del>\(match[1])</del>"
        }
        return html
    }

    private static func replaceRegex(
        _ pattern: String,
        in string: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }

        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else {
            return string
        }

        var result = string
        for match in matches.reversed() {
            let groups = (0..<match.numberOfRanges).map { index in
                match.range(at: index).location == NSNotFound ? "" : nsString.substring(with: match.range(at: index))
            }
            let replacement = transform(groups)
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLPreservingLineBreaks(_ string: String) -> String {
        escapeHTML(string).replacingOccurrences(of: "\n", with: "<br/>")
    }

    private static func looksLikeHTML(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("<"), trimmed.contains(">") else {
            return false
        }

        let markers = [
            "<html",
            "<body",
            "<p",
            "<div",
            "<span",
            "<br",
            "<strong",
            "<b>",
            "<em",
            "<i>",
            "<u>",
            "<sub>",
            "<sup>",
            "<a ",
            "<ul",
            "<ol",
            "<li",
            "<h1",
            "<h2",
            "<h3",
            "<del>",
        ]

        return markers.contains { trimmed.contains($0) }
    }

    private enum MarkdownListType {
        case unordered
        case ordered
    }

    private static func listType(for string: String) -> MarkdownListType? {
        if string.hasPrefix("- ") || string.hasPrefix("* ") || string.hasPrefix("+ ") || string.hasPrefix("•\t") || string.hasPrefix("• ") {
            return .unordered
        }

        let digits = String(string.prefix { $0.isNumber })
        guard !digits.isEmpty else {
            return nil
        }

        let suffix = string.dropFirst(digits.count)
        return suffix.hasPrefix(". ") || suffix.hasPrefix(".\t") ? .ordered : nil
    }

    private static func removeListMarker(from string: String) -> String {
        if string.hasPrefix("- ") || string.hasPrefix("* ") || string.hasPrefix("+ ") {
            return String(string.dropFirst(2))
        }

        if string.hasPrefix("•\t") || string.hasPrefix("• ") {
            return String(string.dropFirst(2))
        }

        let digits = String(string.prefix { $0.isNumber })
        let suffix = string.dropFirst(digits.count)
        if !digits.isEmpty, suffix.hasPrefix(". ") || suffix.hasPrefix(".\t") {
            return String(string.dropFirst(digits.count + 2))
        }

        return string
    }

    private static func markdownListLine(from paragraphText: String, inlineMarkdown: String) -> String? {
        let trimmed = paragraphText.trimmingCharacters(in: .whitespaces)
        guard let listType = listType(for: trimmed) else {
            return nil
        }

        switch listType {
        case .unordered:
            return "- \(inlineMarkdown)"
        case .ordered:
            let digits = String(trimmed.prefix { $0.isNumber })
            let index = digits.isEmpty ? "1" : digits
            return "\(index). \(inlineMarkdown)"
        }
    }

    private static func headingTagAndText(from string: String) -> (String, String) {
        if string.hasPrefix("### ") {
            return ("h3", String(string.dropFirst(4)))
        }
        if string.hasPrefix("## ") {
            return ("h2", String(string.dropFirst(3)))
        }
        return ("h1", String(string.dropFirst(2)))
    }
}

@MainActor
final class RichTextEditorController: ObservableObject {
    weak var textView: NSTextView?
    private let listBulletPrefix = "•\t"

    func attach(_ textView: NSTextView) {
        self.textView = textView
    }

    func applyBold() {
        toggleFontTrait(.boldFontMask)
    }

    func applyItalic() {
        toggleFontTrait(.italicFontMask)
    }

    func applyUnderline() {
        toggleAttribute(.underlineStyle, onValue: NSUnderlineStyle.single.rawValue, offValue: 0)
    }

    func applyStrikethrough() {
        toggleAttribute(.strikethroughStyle, onValue: NSUnderlineStyle.single.rawValue, offValue: 0)
    }

    func applySubscript() {
        toggleBaseline(offset: -4)
    }

    func applySuperscript() {
        toggleBaseline(offset: 4)
    }

    func applyHeading(level: Int?) {
        guard let textView else {
            return
        }

        let lineRange = paragraphRange(in: textView)
        let font: NSFont
        switch level {
        case 1:
            font = RichTextMarkdownCodec.fontWith(size: 28, weight: .bold, italic: false)
        case 2:
            font = RichTextMarkdownCodec.fontWith(size: 22, weight: .bold, italic: false)
        case 3:
            font = RichTextMarkdownCodec.fontWith(size: 18, weight: .bold, italic: false)
        default:
            font = RichTextMarkdownCodec.fontWith(size: 14, weight: .regular, italic: false)
        }

        if textView.selectedRange().length == 0 {
            var typingAttributes = textView.typingAttributes
            typingAttributes[.font] = font
            textView.typingAttributes = sanitizedTypingAttributes(typingAttributes)
            return
        }

        applyAttributes([.font: font], range: lineRange)
    }

    func applyBulletList() {
        transformSelectedLines { lines in
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldRemove = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { isBulletLine($0) }

            return lines.map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return line
                }
                if shouldRemove {
                    return removeListPrefix(from: line)
                }
                return addPrefix(listBulletPrefix, to: line)
            }
        }
    }

    func applyNumberedList() {
        transformSelectedLines { lines in
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldRemove = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { isNumberedLine($0) }

            var index = 1
            return lines.map { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return line
                }
                defer { index += 1 }
                if shouldRemove {
                    return removeListPrefix(from: line)
                }
                return addPrefix("\(index).\t", to: line)
            }
        }
    }

    func insertLink() {
        guard let textView else {
            return
        }

        let selectionRange = textView.selectedRange()
        let selectedText = selectionRange.length > 0
            ? textView.attributedString().attributedSubstring(from: selectionRange).string
            : ""

        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.informativeText = "Add the label and URL for this link."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let labelField = NSTextField(string: selectedText)
        let urlField = NSTextField(string: "https://")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.addArrangedSubview(NSTextField(labelWithString: "Text"))
        stack.addArrangedSubview(labelField)
        stack.addArrangedSubview(NSTextField(labelWithString: "URL"))
        stack.addArrangedSubview(urlField)
        stack.setFrameSize(NSSize(width: 320, height: 110))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let label = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !url.isEmpty else {
            return
        }

        let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let attributed = NSMutableAttributedString(
            string: label,
            attributes: [
                .link: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.linkColor,
                .font: font,
            ]
        )
        replaceSelection(in: textView, range: selectionRange, with: attributed)
        let cursorLocation = selectionRange.location + attributed.length
        textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))

        var typingAttributes = textView.typingAttributes
        typingAttributes.removeValue(forKey: .link)
        typingAttributes.removeValue(forKey: .underlineStyle)
        typingAttributes.removeValue(forKey: .foregroundColor)
        typingAttributes[.font] = font
        textView.typingAttributes = sanitizedTypingAttributes(typingAttributes)
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else {
            return
        }

        let selection = textView.selectedRange()
        if selection.length == 0 {
            var typingAttributes = textView.typingAttributes
            let currentFont = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            typingAttributes[.font] = toggledFont(from: currentFont, trait: trait)
            textView.typingAttributes = sanitizedTypingAttributes(typingAttributes)
            return
        }

        guard let textStorage = textView.textStorage else {
            return
        }

        let shouldEnable = !selectionHasFontTrait(textStorage: textStorage, range: selection, trait: trait)
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selection) { value, subrange, _ in
            let currentFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            textStorage.addAttribute(
                .font,
                value: font(from: currentFont, trait: trait, enabled: shouldEnable),
                range: subrange
            )
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, onValue: Any, offValue: Any) {
        guard let textView else {
            return
        }

        let range = textView.selectedRange()
        if range.length == 0 {
            var typingAttributes = textView.typingAttributes
            let currentValue = typingAttributes[key]
            let shouldEnable = String(describing: currentValue ?? "") != String(describing: onValue)
            if shouldEnable {
                typingAttributes[key] = onValue
            } else {
                typingAttributes.removeValue(forKey: key)
            }
            textView.typingAttributes = sanitizedTypingAttributes(typingAttributes)
            return
        }

        guard let textStorage = textView.textStorage else {
            return
        }

        let shouldEnable = !rangeHasUniformAttribute(textStorage: textStorage, key: key, range: range, targetValue: onValue)
        textStorage.beginEditing()
        if shouldEnable {
            textStorage.addAttribute(key, value: onValue, range: range)
        } else {
            textStorage.removeAttribute(key, range: range)
            if String(describing: offValue) != "0" {
                textStorage.addAttribute(key, value: offValue, range: range)
            }
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(range)
    }

    private func toggleBaseline(offset: CGFloat) {
        guard let textView else {
            return
        }

        let selection = textView.selectedRange()
        let targetSign = offset == 0 ? 0 : (offset > 0 ? 1 : -1)

        if selection.length == 0 {
            var typingAttributes = textView.typingAttributes
            let currentFont = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let currentOffset = (typingAttributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
            let currentSign = currentOffset == 0 ? 0 : (currentOffset > 0 ? 1 : -1)
            let shouldEnable = currentSign != targetSign

            if shouldEnable {
                typingAttributes[.baselineOffset] = offset
            } else {
                typingAttributes.removeValue(forKey: .baselineOffset)
            }

            typingAttributes[.font] = baselineAdjustedFont(
                from: currentFont,
                currentOffset: currentOffset,
                newOffset: shouldEnable ? offset : 0
            )
            textView.typingAttributes = sanitizedTypingAttributes(typingAttributes)
            return
        }

        guard let textStorage = textView.textStorage else {
            return
        }

        let shouldEnable = !selectionHasBaselineSign(textStorage: textStorage, range: selection, sign: targetSign)
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: selection) { attributes, subrange, _ in
            let currentFont = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let currentOffset = (attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
            let newOffset = shouldEnable ? offset : 0

            textStorage.addAttribute(
                .font,
                value: baselineAdjustedFont(from: currentFont, currentOffset: currentOffset, newOffset: newOffset),
                range: subrange
            )

            if shouldEnable {
                textStorage.addAttribute(.baselineOffset, value: offset, range: subrange)
            } else {
                textStorage.removeAttribute(.baselineOffset, range: subrange)
            }
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }

    private func applyAttributes(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
        guard let textView, let textStorage = textView.textStorage else {
            return
        }

        textStorage.beginEditing()
        for (key, value) in attributes {
            textStorage.addAttribute(key, value: value, range: range)
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(range)
    }

    private func paragraphRange(in textView: NSTextView) -> NSRange {
        let nsText = textView.string as NSString
        return nsText.paragraphRange(for: textView.selectedRange())
    }

    private func replaceSelection(in textView: NSTextView, range: NSRange, with attributedString: NSAttributedString) {
        if textView.shouldChangeText(in: range, replacementString: attributedString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: attributedString)
            textView.didChangeText()
            let cursorRange = NSRange(location: range.location + attributedString.length, length: 0)
            textView.setSelectedRange(cursorRange)
            textView.scrollRangeToVisible(cursorRange)
        }
    }

    private func rangeHasUniformAttribute(
        textStorage: NSTextStorage,
        key: NSAttributedString.Key,
        range: NSRange,
        targetValue: Any
    ) -> Bool {
        guard range.length > 0 else {
            return false
        }

        var matches = true
        textStorage.enumerateAttribute(key, in: range) { value, _, stop in
            if String(describing: value ?? "") != String(describing: targetValue) {
                matches = false
                stop.pointee = true
            }
        }
        return matches
    }

    private func transformSelectedLines(_ transform: ([String]) -> [String]) {
        guard let textView else {
            return
        }

        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let paragraphRange = text.paragraphRange(for: selection)
        let selected = text.substring(with: paragraphRange)
        let transformed = transform(selected.components(separatedBy: "\n")).joined(separator: "\n")

        let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let attributed = NSAttributedString(string: transformed, attributes: [.font: font])
        replaceSelection(in: textView, range: paragraphRange, with: attributed)
    }

    private func addPrefix(_ prefix: String, to line: String) -> String {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        return indentation + prefix + line.dropFirst(indentation.count)
    }

    private func removeListPrefix(from line: String) -> String {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = String(line.dropFirst(indentation.count))

        if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") || body.hasPrefix("•\t") || body.hasPrefix("• ") {
            return indentation + body.dropFirst(2)
        }

        let digits = String(body.prefix { $0.isNumber })
        let suffix = body.dropFirst(digits.count)
        if !digits.isEmpty, suffix.hasPrefix(". ") || suffix.hasPrefix(".\t") {
            return indentation + body.dropFirst(digits.count + 2)
        }

        return line
    }

    private func isNumberedLine(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        let digits = String(body.prefix { $0.isNumber })
        let suffix = body.dropFirst(digits.count)
        return !digits.isEmpty && (suffix.hasPrefix(". ") || suffix.hasPrefix(".\t"))
    }

    private func isBulletLine(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        return body.hasPrefix("•\t") || body.hasPrefix("• ")
    }

    private func toggledFont(from currentFont: NSFont, trait: NSFontTraitMask) -> NSFont {
        let traits = NSFontManager.shared.traits(of: currentFont)
        let enabled = !traits.contains(trait)
        return font(from: currentFont, trait: trait, enabled: enabled)
    }

    private func font(from currentFont: NSFont, trait: NSFontTraitMask, enabled: Bool) -> NSFont {
        let traits = NSFontManager.shared.traits(of: currentFont)
        let bold = trait == .boldFontMask ? enabled : traits.contains(.boldFontMask)
        let italic = trait == .italicFontMask ? enabled : traits.contains(.italicFontMask)
        let weight: NSFont.Weight = bold ? .semibold : .regular
        return RichTextMarkdownCodec.fontWith(size: currentFont.pointSize, weight: weight, italic: italic)
    }

    private func selectionHasFontTrait(
        textStorage: NSTextStorage,
        range: NSRange,
        trait: NSFontTraitMask
    ) -> Bool {
        guard range.length > 0 else {
            return false
        }

        var allMatch = true
        textStorage.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let traits = NSFontManager.shared.traits(of: font)
            if !traits.contains(trait) {
                allMatch = false
                stop.pointee = true
            }
        }
        return allMatch
    }

    private func selectionHasBaselineSign(
        textStorage: NSTextStorage,
        range: NSRange,
        sign: Int
    ) -> Bool {
        guard range.length > 0 else {
            return false
        }

        var allMatch = true
        textStorage.enumerateAttribute(.baselineOffset, in: range) { value, _, stop in
            let offset = (value as? NSNumber)?.doubleValue ?? 0
            let currentSign = offset == 0 ? 0 : (offset > 0 ? 1 : -1)
            if currentSign != sign {
                allMatch = false
                stop.pointee = true
            }
        }
        return allMatch
    }

    private func baselineAdjustedFont(from currentFont: NSFont, currentOffset: Double, newOffset: CGFloat) -> NSFont {
        let traits = NSFontManager.shared.traits(of: currentFont)
        let weight: NSFont.Weight = traits.contains(.boldFontMask) ? .semibold : .regular
        let italic = traits.contains(.italicFontMask)

        let hadBaseline = currentOffset != 0
        let willHaveBaseline = newOffset != 0
        let newSize: CGFloat

        switch (hadBaseline, willHaveBaseline) {
        case (false, true):
            newSize = max(round(currentFont.pointSize * 0.8), 11)
        case (true, false):
            newSize = max(round(currentFont.pointSize / 0.8), 14)
        default:
            newSize = currentFont.pointSize
        }

        return RichTextMarkdownCodec.fontWith(size: newSize, weight: weight, italic: italic)
    }

    private func sanitizedTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var sanitized = attributes
        if sanitized[.font] == nil {
            sanitized[.font] = NSFont.systemFont(ofSize: 14)
        }
        return sanitized
    }
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richTextData: Data?
    let controller: RichTextEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, richTextData: $richTextData, controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.defaultParagraphStyle = NSParagraphStyle.default

        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
        }

        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 220)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        let attributed = RichTextMarkdownCodec.attributedString(
            from: Snippet(trigger: "", content: text, richTextData: richTextData)
        )
        textView.textStorage?.setAttributedString(attributed)

        scrollView.documentView = textView
        controller.attach(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        controller.attach(textView)

        if context.coordinator.isUpdatingFromView {
            return
        }

        let target = RichTextMarkdownCodec.attributedString(
            from: Snippet(trigger: "", content: text, richTextData: richTextData)
        )

        if textView.attributedString() != target {
            context.coordinator.isUpdatingFromModel = true
            textView.textStorage?.setAttributedString(target)
            context.coordinator.isUpdatingFromModel = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var richTextData: Data?
        private let controller: RichTextEditorController
        var isUpdatingFromModel = false
        var isUpdatingFromView = false

        init(
            text: Binding<String>,
            richTextData: Binding<Data?>,
            controller: RichTextEditorController
        ) {
            _text = text
            _richTextData = richTextData
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromModel, let textView = notification.object as? NSTextView else {
                return
            }

            controller.attach(textView)
            isUpdatingFromView = true
            text = textView.string
            richTextData = RichTextMarkdownCodec.rtfData(from: textView.attributedString())
            isUpdatingFromView = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let nsText = textView.string as NSString
            let selection = textView.selectedRange()
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: selection.location, length: 0))
            let currentLine = nsText.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
            let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("•\t") || trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2))
                let insertion = content.trimmingCharacters(in: .whitespaces).isEmpty ? "\n" : "\n•\t"
                textView.insertText(insertion, replacementRange: selection)
                return true
            }

            let digits = String(trimmed.prefix { $0.isNumber })
            let suffix = trimmed.dropFirst(digits.count)
            if !digits.isEmpty, suffix.hasPrefix(".\t") || suffix.hasPrefix(". ") {
                let content = String(suffix.dropFirst(2))
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    textView.insertText("\n", replacementRange: selection)
                } else {
                    let nextIndex = (Int(digits) ?? 1) + 1
                    textView.insertText("\n\(nextIndex).\t", replacementRange: selection)
                }
                return true
            }

            return false
        }
    }
}
