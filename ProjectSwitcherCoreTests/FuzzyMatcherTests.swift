import XCTest

@testable import ProjectSwitcherCore

final class FuzzyMatcherTests: XCTestCase {
    // MARK: - Empty / Edge Cases

    func testEmptyQueryReturnsZero() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", target: "Agent Layer"), 0)
    }

    func testEmptyTargetReturnsZero() {
        XCTAssertEqual(FuzzyMatcher.score(query: "al", target: ""), 0)
    }

    func testBothEmptyReturnsZero() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", target: ""), 0)
    }

    func testQueryLongerThanTargetWithNoMatch() {
        XCTAssertEqual(FuzzyMatcher.score(query: "abcdefghij", target: "abc"), 0)
    }

    // MARK: - Prefix Matching (Tier 1, score ~1000)

    func testExactPrefixMatchScoresHighest() {
        let score = FuzzyMatcher.score(query: "Agent", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }

    func testExactFullMatchScoresHighest() {
        let score = FuzzyMatcher.score(query: "Agent Layer", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }

    func testPrefixMatchIsCaseInsensitive() {
        let score = FuzzyMatcher.score(query: "agent", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }

    func testSingleCharPrefixMatch() {
        let score = FuzzyMatcher.score(query: "a", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }

    func testShorterTargetGetsPrefixBonus() {
        let shortScore = FuzzyMatcher.score(query: "a", target: "AB")
        let longScore = FuzzyMatcher.score(query: "a", target: "A Very Long Name")
        XCTAssertGreaterThan(shortScore, longScore)
    }

    // MARK: - Word-Boundary Acronym Matching (Tier 2, score ~800)

    func testWordBoundaryAcronymMatch() {
        // "al" matches "Agent Layer" via A + L word boundaries
        let score = FuzzyMatcher.score(query: "al", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 800)
        XCTAssertLessThan(score, 1000)
    }

    func testWordBoundaryAcronymMatchCaseInsensitive() {
        let score = FuzzyMatcher.score(query: "AL", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testHyphenBoundaryAcronymMatch() {
        // "al" matches "agent-layer" via a + l after hyphen
        let score = FuzzyMatcher.score(query: "al", target: "agent-layer")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testUnderscoreBoundaryAcronymMatch() {
        let score = FuzzyMatcher.score(query: "al", target: "agent_layer")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testCamelCaseBoundaryMatch() {
        // "ps" matches "ProjectSwitcher" via P + S camel-case boundaries.
        let score = FuzzyMatcher.score(query: "ps", target: "ProjectSwitcher")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testThreeWordAcronymMatch() {
        // "rms" matches "Remote ML Server" via R + M + S word boundaries
        let score = FuzzyMatcher.score(query: "rms", target: "Remote ML Server")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testPartialAcronymNoMatch() {
        // "xyz" does not match any word boundaries of "Agent Layer"
        let score = FuzzyMatcher.score(query: "xyz", target: "Agent Layer")
        XCTAssertEqual(score, 0)
    }

    // MARK: - Substring Matching (Tier 3, score ~600)

    func testSubstringMatch() {
        let score = FuzzyMatcher.score(query: "gent", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 600)
        XCTAssertLessThan(score, 800)
    }

    func testSubstringMatchCaseInsensitive() {
        let score = FuzzyMatcher.score(query: "GENT", target: "Agent Layer")
        XCTAssertGreaterThanOrEqual(score, 600)
    }

    func testSubstringEarlierPositionScoresHigher() {
        let earlyScore = FuzzyMatcher.score(query: "gen", target: "Agent Layer")
        let lateScore = FuzzyMatcher.score(query: "yer", target: "Agent Layer")
        XCTAssertGreaterThan(earlyScore, lateScore)
    }

    // MARK: - Fuzzy Matching (Tier 4, score > 0 and < 600)

    func testFuzzyMatchNonConsecutiveChars() {
        // "alr" matches A...L...r in "Agent Layer"
        let score = FuzzyMatcher.score(query: "alr", target: "Agent Layer")
        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThan(score, 600)
    }

    func testFuzzyMatchWithLargeGaps() {
        let score = FuzzyMatcher.score(query: "ar", target: "Agent Layer")
        XCTAssertGreaterThan(score, 0)
    }

    // MARK: - No Match

    func testNoMatchReturnsZero() {
        XCTAssertEqual(FuzzyMatcher.score(query: "xyz", target: "Agent Layer"), 0)
    }

    func testNoMatchWhenCharsCannotBeFoundInOrder() {
        // "zx" cannot be matched in "Agent Layer" — neither char exists
        XCTAssertEqual(FuzzyMatcher.score(query: "zx", target: "Agent Layer"), 0)
    }

    func testFuzzyMatchWhenCharsAppearLaterInTarget() {
        // "la" matches "Agent Layer" via L(6) → a(7) in "Layer"
        let score = FuzzyMatcher.score(query: "la", target: "Agent Layer")
        XCTAssertGreaterThan(score, 0)
    }

    // MARK: - Score Ordering (Critical: higher tier always wins)

    func testPrefixBeatsAcronym() {
        let prefixScore = FuzzyMatcher.score(query: "agent", target: "Agent Layer")
        let acronymScore = FuzzyMatcher.score(query: "al", target: "Agent Layer")
        XCTAssertGreaterThan(prefixScore, acronymScore)
    }

    func testPrefixBeatsLongAcronymRegression() {
        // Regression: long acronym queries with many consecutive boundary matches
        // must not overflow into the prefix tier (acronym capped at 999, prefix floor 1000).
        let target = "Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliet Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango Uniform Victor Whiskey Xray Yankee Zulu"
        let acronym = "abcdefghijklmnopqrstuvwxyz"
        let acronymScore = FuzzyMatcher.score(query: acronym, target: target)
        let prefixScore = FuzzyMatcher.score(query: "alpha", target: target)
        XCTAssertGreaterThan(prefixScore, acronymScore,
            "Prefix must always beat acronym regardless of query length")
        XCTAssertLessThan(acronymScore, 1000,
            "Acronym score must stay below prefix floor (1000)")
    }

    func testAcronymBeatsSubstring() {
        let acronymScore = FuzzyMatcher.score(query: "al", target: "Agent Layer")
        let substringScore = FuzzyMatcher.score(query: "gent", target: "Agent Layer")
        XCTAssertGreaterThan(acronymScore, substringScore)
    }

    func testSubstringBeatsFuzzy() {
        let substringScore = FuzzyMatcher.score(query: "gent", target: "Agent Layer")
        let fuzzyScore = FuzzyMatcher.score(query: "alr", target: "Agent Layer")
        XCTAssertGreaterThan(substringScore, fuzzyScore)
    }

    // MARK: - Roadmap Acceptance Criteria

    func testAlMatchesAgentLayer() {
        let score = FuzzyMatcher.score(query: "al", target: "Agent Layer")
        XCTAssertGreaterThan(score, 0, "'al' must match 'Agent Layer'")
    }

    // MARK: - Special Characters

    func testSpecialCharactersInQuery() {
        let score = FuzzyMatcher.score(query: "a-l", target: "agent-layer")
        XCTAssertGreaterThan(score, 0)
    }

    func testDotBoundaryMatch() {
        let score = FuzzyMatcher.score(query: "fc", target: "foo.config")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    // MARK: - ID-style Matching

    func testIDPrefixMatch() {
        let score = FuzzyMatcher.score(query: "agent", target: "agent-layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }

    func testIDSubstringMatch() {
        let score = FuzzyMatcher.score(query: "layer", target: "agent-layer")
        XCTAssertGreaterThanOrEqual(score, 600)
    }

    func testIDFullMatch() {
        let score = FuzzyMatcher.score(query: "agent-layer", target: "agent-layer")
        XCTAssertGreaterThanOrEqual(score, 1000)
    }
}
