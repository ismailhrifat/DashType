import AppKit
import ApplicationServices
#if canImport(DashTypeCore)
import DashTypeCore
#endif
import Foundation

private let dashTypeInjectedEventMarker: Int64 = 0x4454595045

@MainActor
final class TextExpansionController: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastExpansionDescription = "Waiting for a snippet..."

    private let store: SnippetStore
    private let permissions: PermissionManager
    private let replacementStrategy: TextReplacementStrategy
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentToken = ""
    private var isInjecting = false

    init(
        store: SnippetStore,
        permissions: PermissionManager,
        replacementStrategy: TextReplacementStrategy? = nil
    ) {
        self.store = store
        self.permissions = permissions
        self.replacementStrategy = replacementStrategy
            ?? PasteboardReplacementStrategy(eventMarker: dashTypeInjectedEventMarker)
    }

    func start() {
        guard eventTap == nil else {
            isMonitoring = true
            return
        }

        permissions.refresh()
        guard permissions.accessibilityGranted else {
            lastExpansionDescription = "Accessibility permission is required before DashType can listen globally."
            isMonitoring = false
            return
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<TextExpansionController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return controller.handleTapEvent(type: type, event: event)
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastExpansionDescription = "DashType could not start the keyboard listener. Re-check Accessibility permission and restart the app."
            isMonitoring = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        isMonitoring = true
        lastExpansionDescription = "Listener is running. Try typing a trigger like /greet in another app like TextEdit."
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        isMonitoring = false
        currentToken = ""
        lastExpansionDescription = "Listener stopped."
    }

    func restartIfNeeded() {
        stop()
        start()
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    nonisolated private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
            Task { @MainActor in
                self.reenableEventTap()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let injectedMarker = event.getIntegerValueField(.eventSourceUserData)
        if injectedMarker == dashTypeInjectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let characters = event.unicodeString

        Task { @MainActor in
            self.handle(keyCode: keyCode, characters: characters, flags: flags)
        }

        return Unmanaged.passUnretained(event)
    }

    private func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handle(keyCode: CGKeyCode, characters: String, flags: CGEventFlags) {
        guard !isInjecting else {
            return
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            currentToken = ""
            return
        }

        if keyCode == 51 {
            if !currentToken.isEmpty {
                currentToken.removeLast()
            }
            return
        }

        guard !characters.isEmpty else {
            currentToken = ""
            return
        }

        for character in characters {
            handle(character: character)
        }
    }

    private func handle(character: Character) {
        if SnippetMatcher.tokenResetCharacters.contains(character) {
            currentToken = ""
            return
        }

        guard character.isASCII, !character.isNewline else {
            currentToken = ""
            return
        }

        currentToken.append(character)
        trimBufferIfNeeded()

        guard let match = SnippetMatcher.match(
            currentToken: currentToken,
            snippets: store.enabledSnippets
        ) else {
            return
        }

        currentToken = ""
        lastExpansionDescription = "Detected \(match.snippet.trigger). Replacing text..."
        replaceText(for: match)
        lastExpansionDescription = "\(match.snippet.trigger) -> \(match.snippet.content)"
    }

    private func trimBufferIfNeeded() {
        let longestTrigger = max(store.enabledSnippets.map { $0.trigger.count }.max() ?? 0, 64)
        if currentToken.count > longestTrigger {
            currentToken = String(currentToken.suffix(longestTrigger))
        }
    }

    private func replaceText(for match: SnippetMatch) {
        isInjecting = true
        let attributedString = RichTextMarkdownCodec.attributedString(from: match.snippet)
        replacementStrategy.performReplacement(
            TextReplacementRequest(
                charactersToReplace: match.charactersToReplace,
                replacementText: attributedString.string,
                richTextData: RichTextMarkdownCodec.rtfData(from: attributedString),
                htmlData: RichTextMarkdownCodec.htmlData(from: attributedString)
            )
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            self?.isInjecting = false
        }
    }
}

private extension CGEvent {
    var unicodeString: String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )

        guard length > 0 else {
            return ""
        }

        return String(utf16CodeUnits: buffer, count: length)
    }
}
