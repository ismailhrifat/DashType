import AppKit
import ApplicationServices
import Foundation

struct TextReplacementRequest: Sendable {
    let charactersToReplace: Int
    let replacementText: String
    let richTextData: Data?
    let htmlData: Data?
    let cursorLocationUTF16: Int?
    let cursorMoveLeftCount: Int
}

@MainActor
protocol TextReplacementStrategy {
    func performReplacement(_ request: TextReplacementRequest)
}

@MainActor
final class PasteboardReplacementStrategy: TextReplacementStrategy {
    private let eventMarker: Int64
    private let pasteKeyCode: CGKeyCode
    private let leftArrowKeyCode: CGKeyCode
    private let restoreDelay: TimeInterval

    init(
        eventMarker: Int64,
        pasteKeyCode: CGKeyCode = 9,
        leftArrowKeyCode: CGKeyCode = 123,
        restoreDelay: TimeInterval = 0.18
    ) {
        self.eventMarker = eventMarker
        self.pasteKeyCode = pasteKeyCode
        self.leftArrowKeyCode = leftArrowKeyCode
        self.restoreDelay = restoreDelay
    }

    func performReplacement(_ request: TextReplacementRequest) {
        let accessibilityTarget = captureAccessibilityCaretTarget(for: request)
        let snapshot = capturePasteboard()
        writePasteboard(
            text: request.replacementText,
            richTextData: request.richTextData,
            htmlData: request.htmlData
        )
        let charactersToReplace = request.charactersToReplace
        let pasteKeyCode = self.pasteKeyCode
        let leftArrowKeyCode = self.leftArrowKeyCode
        let eventMarker = self.eventMarker
        let restoreDelay = self.restoreDelay
        let cursorMoveLeftCount = request.cursorMoveLeftCount

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            let source = CGEventSource(stateID: .hidSystemState)

            for _ in 0..<charactersToReplace {
                postKeyStroke(keyCode: 51, source: source, eventMarker: eventMarker)
            }

            postModifiedKeyStroke(
                keyCode: pasteKeyCode,
                flags: .maskCommand,
                source: source,
                eventMarker: eventMarker
            )

            guard cursorMoveLeftCount > 0 else {
                return
            }

            if let accessibilityTarget,
               await moveCaret(to: accessibilityTarget) {
                return
            }

            try? await Task.sleep(for: .milliseconds(60))
            for _ in 0..<cursorMoveLeftCount {
                postKeyStroke(keyCode: leftArrowKeyCode, source: source, eventMarker: eventMarker)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(restoreDelay))
            restorePasteboard(snapshot)
        }
    }

    private func capturePasteboard() -> [[String: Data]] {
        let pasteboard = NSPasteboard.general
        return (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    stored[type.rawValue] = data
                }
            }
            return stored
        }
    }

    private func writePasteboard(text: String, richTextData: Data?, htmlData: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if let richTextData {
            pasteboard.setData(richTextData, forType: .rtf)
        }

        if let htmlData {
            pasteboard.setData(htmlData, forType: .html)
        }
    }

    private func restorePasteboard(_ snapshot: [[String: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !snapshot.isEmpty else {
            return
        }

        let items = snapshot.compactMap { storedTypes -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            for (type, data) in storedTypes {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }

        pasteboard.writeObjects(items)
    }

    private func captureAccessibilityCaretTarget(for request: TextReplacementRequest) -> AccessibilityCaretTarget? {
        guard let cursorLocationUTF16 = request.cursorLocationUTF16 else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedElement = focusedValue,
        CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let element = unsafeDowncast(focusedElement, to: AXUIElement.self)
        guard let selectedRange = selectedTextRange(for: element) else {
            return nil
        }

        let insertionStart = max(selectedRange.location - request.charactersToReplace, 0)
        let targetRange = CFRange(location: insertionStart + cursorLocationUTF16, length: 0)
        return AccessibilityCaretTarget(element: element, selectedRange: targetRange)
    }

    private func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedValue
        ) == .success,
        let selectedValue,
        CFGetTypeID(selectedValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let rangeValue = unsafeDowncast(selectedValue, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func setSelectedTextRange(_ range: CFRange, for element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }

    private func moveCaret(to target: AccessibilityCaretTarget) async -> Bool {
        for attempt in 0..<6 {
            let delay = attempt == 0 ? 50 : 35
            try? await Task.sleep(for: .milliseconds(delay))

            guard setSelectedTextRange(target.selectedRange, for: target.element) else {
                continue
            }

            if let currentRange = selectedTextRange(for: target.element),
               currentRange.location == target.selectedRange.location,
               currentRange.length == target.selectedRange.length {
                return true
            }
        }

        return false
    }
}

private struct AccessibilityCaretTarget {
    let element: AXUIElement
    let selectedRange: CFRange
}

private func postKeyStroke(keyCode: CGKeyCode, source: CGEventSource?, eventMarker: Int64) {
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyDown?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
    keyUp?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

private func postModifiedKeyStroke(
    keyCode: CGKeyCode,
    flags: CGEventFlags,
    source: CGEventSource?,
    eventMarker: Int64
) {
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags
    keyDown?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
    keyUp?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
