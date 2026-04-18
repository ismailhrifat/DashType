#if canImport(Testing)
import Testing
@testable import DashTypeCore

@Test func leavesPlainSnippetTextUntouched() {
    let processed = SnippetCommandProcessor.process("Hello there")

    #expect(processed.text == "Hello there")
    #expect(processed.cursorLocation == nil)
    #expect(processed.cursorLocationUTF16 == nil)
    #expect(processed.cursorMoveLeftCount == 0)
}

@Test func stripsCursorCommandAndTracksInsertionPoint() {
    let processed = SnippetCommandProcessor.process("Hello {cursor}, how are you?")

    #expect(processed.text == "Hello , how are you?")
    #expect(processed.cursorLocation == 6)
    #expect(processed.cursorLocationUTF16 == 6)
    #expect(processed.cursorMoveLeftCount == 14)
}

@Test func usesFirstCursorCommandWhenMultipleArePresent() {
    let processed = SnippetCommandProcessor.process("{cursor}Hello {cursor}there")

    #expect(processed.text == "Hello there")
    #expect(processed.cursorLocation == 0)
    #expect(processed.cursorLocationUTF16 == 0)
    #expect(processed.cursorMoveLeftCount == 11)
}

@Test func preservesWhitespaceBeforeCursorCommand() {
    let processed = SnippetCommandProcessor.process("Hello {cursor}")

    #expect(processed.text == "Hello ")
    #expect(processed.cursorLocation == 6)
    #expect(processed.cursorLocationUTF16 == 6)
}
#elseif canImport(XCTest)
import XCTest
@testable import DashTypeCore

final class SnippetCommandProcessorTests: XCTestCase {
    func testLeavesPlainSnippetTextUntouched() {
        let processed = SnippetCommandProcessor.process("Hello there")

        XCTAssertEqual(processed.text, "Hello there")
        XCTAssertNil(processed.cursorLocation)
        XCTAssertNil(processed.cursorLocationUTF16)
        XCTAssertEqual(processed.cursorMoveLeftCount, 0)
    }

    func testStripsCursorCommandAndTracksInsertionPoint() {
        let processed = SnippetCommandProcessor.process("Hello {cursor}, how are you?")

        XCTAssertEqual(processed.text, "Hello , how are you?")
        XCTAssertEqual(processed.cursorLocation, 6)
        XCTAssertEqual(processed.cursorLocationUTF16, 6)
        XCTAssertEqual(processed.cursorMoveLeftCount, 14)
    }

    func testUsesFirstCursorCommandWhenMultipleArePresent() {
        let processed = SnippetCommandProcessor.process("{cursor}Hello {cursor}there")

        XCTAssertEqual(processed.text, "Hello there")
        XCTAssertEqual(processed.cursorLocation, 0)
        XCTAssertEqual(processed.cursorLocationUTF16, 0)
        XCTAssertEqual(processed.cursorMoveLeftCount, 11)
    }

    func testPreservesWhitespaceBeforeCursorCommand() {
        let processed = SnippetCommandProcessor.process("Hello {cursor}")

        XCTAssertEqual(processed.text, "Hello ")
        XCTAssertEqual(processed.cursorLocation, 6)
        XCTAssertEqual(processed.cursorLocationUTF16, 6)
    }
}
#endif
