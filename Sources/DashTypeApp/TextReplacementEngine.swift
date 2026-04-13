import AppKit
import ApplicationServices
import Foundation

struct TextReplacementRequest: Sendable {
    let charactersToReplace: Int
    let replacementText: String
    let richTextData: Data?
    let htmlData: Data?
}

@MainActor
protocol TextReplacementStrategy {
    func performReplacement(_ request: TextReplacementRequest)
}

@MainActor
final class PasteboardReplacementStrategy: TextReplacementStrategy {
    private let eventMarker: Int64
    private let pasteKeyCode: CGKeyCode
    private let restoreDelay: TimeInterval

    init(
        eventMarker: Int64,
        pasteKeyCode: CGKeyCode = 9,
        restoreDelay: TimeInterval = 0.18
    ) {
        self.eventMarker = eventMarker
        self.pasteKeyCode = pasteKeyCode
        self.restoreDelay = restoreDelay
    }

    func performReplacement(_ request: TextReplacementRequest) {
        let snapshot = capturePasteboard()
        writePasteboard(
            text: request.replacementText,
            richTextData: request.richTextData,
            htmlData: request.htmlData
        )
        let charactersToReplace = request.charactersToReplace
        let pasteKeyCode = self.pasteKeyCode
        let eventMarker = self.eventMarker
        let restoreDelay = self.restoreDelay

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
