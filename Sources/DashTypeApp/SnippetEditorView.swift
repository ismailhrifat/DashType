#if canImport(DashTypeCore)
import DashTypeCore
#endif
import SwiftUI

struct SnippetEditorView: View {
    let snippet: Snippet
    let sidebarIsVisible: Bool
    let onSave: (Snippet.ID, String, String, String, Data?, Bool) -> Bool
    let onDelete: (Snippet.ID) -> Void
    let duplicateTriggerOwnerTitle: (Snippet.ID, String) -> String?

    @State private var title: String
    @State private var trigger: String
    @State private var content: String
    @State private var richTextData: Data?
    @State private var isEnabled: Bool
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showingDeleteConfirmation = false
    @State private var failedSaveDueToConflict = false
    @StateObject private var richTextEditor = RichTextEditorController()

    init(
        snippet: Snippet,
        sidebarIsVisible: Bool,
        onSave: @escaping (Snippet.ID, String, String, String, Data?, Bool) -> Bool,
        onDelete: @escaping (Snippet.ID) -> Void,
        duplicateTriggerOwnerTitle: @escaping (Snippet.ID, String) -> String?
    ) {
        self.snippet = snippet
        self.sidebarIsVisible = sidebarIsVisible
        self.onSave = onSave
        self.onDelete = onDelete
        self.duplicateTriggerOwnerTitle = duplicateTriggerOwnerTitle
        _title = State(initialValue: snippet.title)
        _trigger = State(initialValue: snippet.trigger)
        _content = State(initialValue: snippet.content)
        _richTextData = State(initialValue: snippet.richTextData)
        _isEnabled = State(initialValue: snippet.isEnabled)
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                topBar

                VStack(alignment: .leading, spacing: 20) {
                    fieldCard
                    editorArea
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onChange(of: snippet) { _, newValue in
            title = newValue.title
            trigger = newValue.trigger
            content = newValue.content
            richTextData = newValue.richTextData
            isEnabled = newValue.isEnabled
        }
        .onChange(of: title) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: trigger) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: content) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: richTextData) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: isEnabled) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            autosaveTask = nil

            if currentDraft != persistedDraft {
                save()
            }
        }
        .alert(
            "Delete Snippet?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(snippet.id)
            }
        } message: {
            Text("This will permanently delete this snippet.")
        }
    }

    private var topBar: some View {
        HStack {
            Text("Snippet Details")
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .padding(.leading, sidebarIsVisible ? 24 : 150)
        .padding(.trailing, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.35)
        }
    }

    private var fieldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Trigger", systemImage: "command")
                        .font(.headline)

                    TextField("/greet", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Title", systemImage: "textformat")
                        .font(.headline)

                    TextField("Greeting", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("For best experience, add a special character like / or - before the command so that it does not conflict with regular typing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Toggle("Enabled", isOn: $isEnabled)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Expanded Text", systemImage: "text.alignleft")
                    .font(.headline)
            }

            formattingToolbar

            MarkdownTextEditor(
                text: $content,
                richTextData: $richTextData,
                controller: richTextEditor
            )
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.04))
                )

            typingHint
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var editorArea: some View {
        HStack(alignment: .top, spacing: 20) {
            contentCard

            commandsCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Commands", systemImage: "terminal")
                .font(.headline)

            commandButton(
                title: "Cursor",
                token: SnippetCommandProcessor.cursorToken,
                statusText: containsCursorCommand ? "Already Used" : nil,
                statusColor: .red,
                disabled: containsCursorCommand,
                action: {
                    richTextEditor.insertCursorCommandIfNeeded()
                },
                detail: {
                    Text("Cursor location after text expansion")
                }
            )
            .help(
                containsCursorCommand
                    ? "Only one \(SnippetCommandProcessor.cursorToken) can be used in a snippet."
                    : "Insert \(SnippetCommandProcessor.cursorToken)"
            )

            commandButton(
                title: "Clipboard",
                token: SnippetCommandProcessor.clipboardToken,
                action: {
                    richTextEditor.insertClipboardCommand()
                },
                detail: {
                    Text("Add clipboard content")
                }
            )
            .help("Insert \(SnippetCommandProcessor.clipboardToken)")

            commandButton(
                title: "Add Text",
                token: SnippetCommandProcessor.addTextToken,
                statusText: containsAddTextCommand ? "Already Used" : nil,
                statusColor: .red,
                disabled: containsAddTextCommand,
                action: {
                    richTextEditor.insertAddTextCommandIfNeeded()
                },
                detail: {
                    Text("Insert custom text. Type ")
                    + Text("{Custom Text}\(triggerPreview)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    + Text(" to use.")
                }
            )
            .help(
                containsAddTextCommand
                    ? "Only one \(SnippetCommandProcessor.addTextToken) can be used in a snippet."
                    : "Insert \(SnippetCommandProcessor.addTextToken)"
            )

            Spacer(minLength: 0)
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func commandButton<Detail: View>(
        title: String,
        token: String,
        statusText: String? = nil,
        statusColor: Color = .secondary,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    (
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        +
                        (statusText.map {
                            Text(" (\($0))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(statusColor)
                        } ?? Text(""))
                    )

                    Spacer(minLength: 8)

                    Text(token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }

                detail()
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toolbarButton("B") {
                    richTextEditor.applyBold()
                }

                toolbarButton("I") {
                    richTextEditor.applyItalic()
                }

                toolbarButton("U") {
                    richTextEditor.applyUnderline()
                }

                toolbarButton("S") {
                    richTextEditor.applyStrikethrough()
                }

                Button {
                    richTextEditor.insertLink()
                } label: {
                    Image(systemName: "link")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .help("Insert Link")

                Menu {
                    Button("Body") {
                        richTextEditor.applyHeading(level: nil)
                    }
                    Button("Title") {
                        richTextEditor.applyHeading(level: 1)
                    }
                    Button("Heading") {
                        richTextEditor.applyHeading(level: 2)
                    }
                    Button("Subheading") {
                        richTextEditor.applyHeading(level: 3)
                    }
                } label: {
                    Label("Style", systemImage: "textformat.size")
                }
                .menuStyle(.borderlessButton)

                Button {
                    richTextEditor.applyBulletList()
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .help("Bullet List")

                Button {
                    richTextEditor.applyNumberedList()
                } label: {
                    Image(systemName: "list.number")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .help("Numbered List")

                toolbarButton("X₂") {
                    richTextEditor.applySubscript()
                }

                toolbarButton("X²") {
                    richTextEditor.applySuperscript()
                }
            }
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard triggerConflictTitle == nil else {
            failedSaveDueToConflict = true
            return false
        }

        let didSave = onSave(
            snippet.id,
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            content,
            richTextData,
            isEnabled
        )

        failedSaveDueToConflict = !didSave
        return didSave
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()

        let draft = currentDraft
        guard draft != persistedDraft else {
            autosaveTask = nil
            return
        }

        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else {
                return
            }

            guard self.currentDraft == draft else {
                return
            }

            self.save()
            self.autosaveTask = nil
        }
    }

    private var currentDraft: DraftState {
        DraftState(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            richTextData: richTextData,
            isEnabled: isEnabled
        )
    }

    private var persistedDraft: DraftState {
        DraftState(
            title: snippet.title.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            content: snippet.content,
            richTextData: snippet.richTextData,
            isEnabled: snippet.isEnabled
        )
    }

    private var typingHint: Text {
        let commandName = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if commandName.isEmpty {
            return Text("Try typing this command anywhere in this Mac.")
                .foregroundStyle(.secondary)
        }

        return Text("Try typing ")
            .foregroundStyle(.secondary)
        + Text(commandName)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Color.accentColor)
        + Text(" anywhere in this Mac.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func toolbarButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private var triggerConflictTitle: String? {
        duplicateTriggerOwnerTitle(
            snippet.id,
            trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var conflictMessage: String? {
        guard let ownerTitle = triggerConflictTitle else {
            return nil
        }

        let displayTitle = ownerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : ownerTitle
        return "This trigger conflicts with \"\(displayTitle)\"."
    }

    private var containsCursorCommand: Bool {
        content.contains(SnippetCommandProcessor.cursorToken)
    }

    private var containsAddTextCommand: Bool {
        content.contains(SnippetCommandProcessor.addTextToken)
    }

    private var triggerPreview: String {
        let normalizedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTrigger.isEmpty ? "/trigger" : normalizedTrigger
    }
}

private struct DraftState: Equatable {
    let title: String
    let trigger: String
    let content: String
    let richTextData: Data?
    let isEnabled: Bool
}
