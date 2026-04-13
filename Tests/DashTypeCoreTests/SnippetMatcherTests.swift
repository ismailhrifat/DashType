#if canImport(Testing)
import Testing
@testable import DashTypeCore

@Test func matchesEnabledSnippetImmediately() {
    let snippet = Snippet(trigger: "/greet", content: "Hi, how are you?")

    let match = SnippetMatcher.match(
        currentToken: "/greet",
        snippets: [snippet]
    )

    #expect(match?.snippet == snippet)
    #expect(match?.replacementText == "Hi, how are you?")
    #expect(match?.charactersToReplace == 6)
}

@Test func matchesPlainWordTriggerImmediately() {
    let snippet = Snippet(trigger: "greet", content: "Hi, how are you?")

    let match = SnippetMatcher.match(
        currentToken: "greet",
        snippets: [snippet]
    )

    #expect(match?.snippet == snippet)
    #expect(match?.replacementText == "Hi, how are you?")
    #expect(match?.charactersToReplace == 5)
}

@Test func matchesSemicolonPrefixedTriggerImmediately() {
    let snippet = Snippet(trigger: ";greet", content: "Hi, how are you?")

    let match = SnippetMatcher.match(
        currentToken: ";greet",
        snippets: [snippet]
    )

    #expect(match?.snippet == snippet)
    #expect(match?.replacementText == "Hi, how are you?")
    #expect(match?.charactersToReplace == 6)
}

@Test func ignoresDisabledSnippets() {
    let snippet = Snippet(trigger: "/greet", content: "Hi", isEnabled: false)

    let match = SnippetMatcher.match(
        currentToken: "/greet",
        snippets: [snippet]
    )

    #expect(match == nil)
}

@Test func requiresExactTriggerMatch() {
    let snippet = Snippet(trigger: "/greet", content: "Hi")

    let match = SnippetMatcher.match(
        currentToken: "/gree",
        snippets: [snippet]
    )

    #expect(match == nil)
}
#elseif canImport(XCTest)
import XCTest
@testable import DashTypeCore

final class SnippetMatcherTests: XCTestCase {
    func testMatchesEnabledSnippetImmediately() {
        let snippet = Snippet(trigger: "/greet", content: "Hi, how are you?")

        let match = SnippetMatcher.match(
            currentToken: "/greet",
            snippets: [snippet]
        )

        XCTAssertEqual(match?.snippet, snippet)
        XCTAssertEqual(match?.replacementText, "Hi, how are you?")
        XCTAssertEqual(match?.charactersToReplace, 6)
    }

    func testMatchesPlainWordTriggerImmediately() {
        let snippet = Snippet(trigger: "greet", content: "Hi, how are you?")

        let match = SnippetMatcher.match(
            currentToken: "greet",
            snippets: [snippet]
        )

        XCTAssertEqual(match?.snippet, snippet)
        XCTAssertEqual(match?.replacementText, "Hi, how are you?")
        XCTAssertEqual(match?.charactersToReplace, 5)
    }

    func testMatchesSemicolonPrefixedTriggerImmediately() {
        let snippet = Snippet(trigger: ";greet", content: "Hi, how are you?")

        let match = SnippetMatcher.match(
            currentToken: ";greet",
            snippets: [snippet]
        )

        XCTAssertEqual(match?.snippet, snippet)
        XCTAssertEqual(match?.replacementText, "Hi, how are you?")
        XCTAssertEqual(match?.charactersToReplace, 6)
    }

    func testIgnoresDisabledSnippets() {
        let snippet = Snippet(trigger: "/greet", content: "Hi", isEnabled: false)

        let match = SnippetMatcher.match(
            currentToken: "/greet",
            snippets: [snippet]
        )

        XCTAssertNil(match)
    }

    func testRequiresExactTriggerMatch() {
        let snippet = Snippet(trigger: "/greet", content: "Hi")

        let match = SnippetMatcher.match(
            currentToken: "/gree",
            snippets: [snippet]
        )

        XCTAssertNil(match)
    }
}
#endif
