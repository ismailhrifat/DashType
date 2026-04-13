#if canImport(Testing)
import Foundation
import Testing
@testable import DashTypeCore

@MainActor
@Test func bootstrapsSampleSnippetWhenStoreIsEmpty() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)

    #expect(store.folders.count == 1)
    #expect(store.folders.first?.name == "My Snippets")
    #expect(store.folders.first?.snippets.first?.trigger == "/greet")
}

@MainActor
@Test func persistsSnippetUpdatesInsideFolders() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let snippet = try #require(store.folders.first?.snippets.first)

    store.updateSnippet(
        id: snippet.id,
        title: "Farewell",
        trigger: "/bye",
        content: "Bye now",
        isEnabled: true
    )

    let reloaded = SnippetStore(fileURL: fileURL)

    #expect(reloaded.folders.first?.snippets.first?.title == "Farewell")
    #expect(reloaded.folders.first?.snippets.first?.trigger == "/bye")
    #expect(reloaded.folders.first?.snippets.first?.content == "Bye now")
}

@MainActor
@Test func rejectsDuplicateSnippetTriggers() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let folder = try #require(store.folders.first)
    let firstSnippet = try #require(folder.snippets.first)
    let secondSnippet = try #require(store.createSnippet(in: folder.id))

    let didSave = store.updateSnippet(
        id: secondSnippet.id,
        title: "Duplicate",
        trigger: firstSnippet.trigger,
        content: "Conflict",
        isEnabled: true
    )

    #expect(didSave == false)
    #expect(store.snippet(id: secondSnippet.id)?.trigger == secondSnippet.trigger)
    #expect(store.conflictingSnippet(for: firstSnippet.trigger, excluding: secondSnippet.id)?.id == firstSnippet.id)
}

@MainActor
@Test func rejectsPrefixConflictsBetweenSnippetTriggers() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let firstSnippet = try #require(store.folders.first?.snippets.first)

    store.updateSnippet(
        id: firstSnippet.id,
        title: "Greeting",
        trigger: "/greet",
        content: "Hello",
        isEnabled: true
    )

    #expect(store.conflictingSnippet(for: "/", excluding: nil)?.id == firstSnippet.id)
    #expect(store.conflictingSnippet(for: "/g", excluding: nil)?.id == firstSnippet.id)
    #expect(store.conflictingSnippet(for: "/gr", excluding: nil)?.id == firstSnippet.id)
    #expect(store.conflictingSnippet(for: "/gre", excluding: nil)?.id == firstSnippet.id)
    #expect(store.conflictingSnippet(for: "/gree", excluding: nil)?.id == firstSnippet.id)
    #expect(store.conflictingSnippet(for: "/greet", excluding: nil)?.id == firstSnippet.id)
}

@MainActor
@Test func migratesLegacyFlatSnippetFilesIntoDefaultFolder() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let fileURL = directory.appendingPathComponent("snippets.json")
    let legacySnippet = Snippet(title: "Legacy", trigger: "/legacy", content: "From old format")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode([legacySnippet])
    try data.write(to: fileURL)

    let store = SnippetStore(fileURL: fileURL)

    #expect(store.folders.count == 1)
    #expect(store.folders.first?.name == "My Snippets")
    #expect(store.folders.first?.snippets.first?.trigger == "/legacy")
}

@MainActor
@Test func disablingFolderRemovesItsSnippetsFromEnabledMatches() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let folder = try #require(store.folders.first)

    store.toggleFolder(folder.id, isEnabled: false)

    #expect(store.folders.first?.isEnabled == false)
    #expect(store.enabledSnippets.isEmpty)
}

@MainActor
@Test func deletingFolderRemovesItsSnippets() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let folder = try #require(store.folders.first)

    store.deleteFolder(folder.id)

    #expect(store.folders.isEmpty)
    #expect(store.enabledSnippets.isEmpty)
}

@MainActor
@Test func renamingFolderPersistsNewName() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let folder = try #require(store.folders.first)

    store.renameFolder(folder.id, name: "Work")

    let reloaded = SnippetStore(fileURL: fileURL)

    #expect(reloaded.folders.first?.name == "Work")
}

@MainActor
@Test func exportDocumentIncludesOnlyTransferFields() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let folder = try #require(store.folders.first)
    let document = store.exportDocument(for: [folder.id])
    let exportedFolder = try #require(document.folders.first)
    let exportedSnippet = try #require(exportedFolder.snippets.first)

    #expect(exportedFolder.name == "My Snippets")
    #expect(exportedSnippet.trigger == "/greet")
    #expect(exportedSnippet.title == "Greeting")
    #expect(exportedSnippet.expandedText == "Hi, how are you?")
}

@MainActor
@Test func importingFoldersAppendsThemWithUniqueNames() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("snippets.json")

    let store = SnippetStore(fileURL: fileURL)
    let imported = store.importFolders(
        from: [
            SnippetTransferFolder(
                name: "My Snippets",
                snippets: [
                    SnippetTransferSnippet(
                        trigger: "/wave",
                        title: "Wave",
                        expandedText: "Hello\nthere"
                    ),
                ]
            ),
        ]
    )

    #expect(imported.first?.name == "My Snippets 2")
    #expect(imported.first?.snippets.first?.content == "Hello\nthere")
}

@Test func htmlTransferDocumentPreservesFormattingAndNewlines() throws {
    let document = SnippetTransferDocument(
        folders: [
            SnippetTransferFolder(
                name: "Docs",
                snippets: [
                    SnippetTransferSnippet(
                        trigger: "/html",
                        title: "Rich Text",
                        expandedText: "<html><body><h1>Heading</h1><p><strong>Bold</strong><br/><u>Under</u></p><ol><li>Item</li></ol></body></html>"
                    ),
                ]
            ),
        ]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(document)
    let json = try #require(String(data: data, encoding: .utf8))
    let decoded = try JSONDecoder().decode(SnippetTransferDocument.self, from: data)

    #expect(json.contains("\"expanded_text\""))
    #expect(decoded == document)
}
#elseif canImport(XCTest)
import Foundation
import XCTest
@testable import DashTypeCore

@MainActor
final class SnippetStoreTests: XCTestCase {
    func testBootstrapsSampleSnippetWhenStoreIsEmpty() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)

        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first?.name, "My Snippets")
        XCTAssertEqual(store.folders.first?.snippets.first?.trigger, "/greet")
    }

    func testPersistsSnippetUpdatesInsideFolders() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let snippet = try XCTUnwrap(store.folders.first?.snippets.first)

        store.updateSnippet(
            id: snippet.id,
            title: "Farewell",
            trigger: "/bye",
            content: "Bye now",
            isEnabled: true
        )

        let reloaded = SnippetStore(fileURL: fileURL)

        XCTAssertEqual(reloaded.folders.first?.snippets.first?.title, "Farewell")
        XCTAssertEqual(reloaded.folders.first?.snippets.first?.trigger, "/bye")
        XCTAssertEqual(reloaded.folders.first?.snippets.first?.content, "Bye now")
    }

    func testRejectsDuplicateSnippetTriggers() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let folder = try XCTUnwrap(store.folders.first)
        let firstSnippet = try XCTUnwrap(folder.snippets.first)
        let secondSnippet = try XCTUnwrap(store.createSnippet(in: folder.id))

        let didSave = store.updateSnippet(
            id: secondSnippet.id,
            title: "Duplicate",
            trigger: firstSnippet.trigger,
            content: "Conflict",
            isEnabled: true
        )

        XCTAssertFalse(didSave)
        XCTAssertEqual(store.snippet(id: secondSnippet.id)?.trigger, secondSnippet.trigger)
        XCTAssertEqual(store.conflictingSnippet(for: firstSnippet.trigger, excluding: secondSnippet.id)?.id, firstSnippet.id)
    }

    func testRejectsPrefixConflictsBetweenSnippetTriggers() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let firstSnippet = try XCTUnwrap(store.folders.first?.snippets.first)

        _ = store.updateSnippet(
            id: firstSnippet.id,
            title: "Greeting",
            trigger: "/greet",
            content: "Hello",
            isEnabled: true
        )

        XCTAssertEqual(store.conflictingSnippet(for: "/", excluding: nil)?.id, firstSnippet.id)
        XCTAssertEqual(store.conflictingSnippet(for: "/g", excluding: nil)?.id, firstSnippet.id)
        XCTAssertEqual(store.conflictingSnippet(for: "/gr", excluding: nil)?.id, firstSnippet.id)
        XCTAssertEqual(store.conflictingSnippet(for: "/gre", excluding: nil)?.id, firstSnippet.id)
        XCTAssertEqual(store.conflictingSnippet(for: "/gree", excluding: nil)?.id, firstSnippet.id)
        XCTAssertEqual(store.conflictingSnippet(for: "/greet", excluding: nil)?.id, firstSnippet.id)
    }

    func testMigratesLegacyFlatSnippetFilesIntoDefaultFolder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("snippets.json")
        let legacySnippet = Snippet(title: "Legacy", trigger: "/legacy", content: "From old format")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([legacySnippet])
        try data.write(to: fileURL)

        let store = SnippetStore(fileURL: fileURL)

        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first?.name, "My Snippets")
        XCTAssertEqual(store.folders.first?.snippets.first?.trigger, "/legacy")
    }

    func testDisablingFolderRemovesItsSnippetsFromEnabledMatches() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let folder = try XCTUnwrap(store.folders.first)

        store.toggleFolder(folder.id, isEnabled: false)

        XCTAssertEqual(store.folders.first?.isEnabled, false)
        XCTAssertTrue(store.enabledSnippets.isEmpty)
    }

    func testDeletingFolderRemovesItsSnippets() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let folder = try XCTUnwrap(store.folders.first)

        store.deleteFolder(folder.id)

        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.enabledSnippets.isEmpty)
    }

    func testRenamingFolderPersistsNewName() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let folder = try XCTUnwrap(store.folders.first)

        store.renameFolder(folder.id, name: "Work")

        let reloaded = SnippetStore(fileURL: fileURL)

        XCTAssertEqual(reloaded.folders.first?.name, "Work")
    }

    func testExportDocumentIncludesOnlyTransferFields() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let folder = try XCTUnwrap(store.folders.first)
        let document = store.exportDocument(for: [folder.id])
        let exportedFolder = try XCTUnwrap(document.folders.first)
        let exportedSnippet = try XCTUnwrap(exportedFolder.snippets.first)

        XCTAssertEqual(exportedFolder.name, "My Snippets")
        XCTAssertEqual(exportedSnippet.trigger, "/greet")
        XCTAssertEqual(exportedSnippet.title, "Greeting")
        XCTAssertEqual(exportedSnippet.expandedText, "Hi, how are you?")
    }

    func testImportingFoldersAppendsThemWithUniqueNames() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snippets.json")

        let store = SnippetStore(fileURL: fileURL)
        let imported = store.importFolders(
            from: [
                SnippetTransferFolder(
                    name: "My Snippets",
                    snippets: [
                        SnippetTransferSnippet(
                            trigger: "/wave",
                            title: "Wave",
                            expandedText: "Hello\nthere"
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(imported.first?.name, "My Snippets 2")
        XCTAssertEqual(imported.first?.snippets.first?.content, "Hello\nthere")
    }

    func testHTMLTransferDocumentPreservesFormattingAndNewlines() throws {
        let document = SnippetTransferDocument(
            folders: [
                SnippetTransferFolder(
                    name: "Docs",
                    snippets: [
                        SnippetTransferSnippet(
                            trigger: "/html",
                            title: "Rich Text",
                            expandedText: "<html><body><h1>Heading</h1><p><strong>Bold</strong><br/><u>Under</u></p><ol><li>Item</li></ol></body></html>"
                        )
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(document)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(SnippetTransferDocument.self, from: data)

        XCTAssertTrue(json.contains("\"expanded_text\""))
        XCTAssertEqual(decoded, document)
    }
}
#endif
