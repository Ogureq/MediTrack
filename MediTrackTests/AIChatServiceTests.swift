import XCTest
@testable import MediTrack

/// Pure, network-free tests for `AIChatService.buildContext` and
/// `AIChatService.trimmedHistory`. `AIChatService.reply` itself is not
/// exercised here — it makes a live network call.
final class AIChatServiceTests: XCTestCase {

    private func makeFixedDate() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 9
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: buildContext

    private func makeReview(findings: [Finding], date: Date) -> HealthReview {
        HealthReview(
            generatedAt: date,
            hasData: true,
            score: 82,
            summary: "Reviewed 4 lab results, 3 vital readings.",
            findings: findings,
            trends: [],
            labSnapshots: []
        )
    }

    func testBuildContextContainsScoreAndScoreLabel() throws {
        let review = makeReview(findings: [], date: try makeFixedDate())
        let context = AIChatService.buildContext(review: review, profileSummary: "")

        XCTAssertTrue(context.contains("82"))
        XCTAssertTrue(context.contains(review.scoreLabel))
    }

    func testBuildContextContainsEveryFindingTitle() throws {
        let findings = [
            Finding(severity: .critical, category: .labs, title: "Potassium is at a critical level", detail: "Latest value 6.8 mmol/L.", recommendation: "Contact your doctor promptly."),
            Finding(severity: .attention, category: .vitals, title: "Blood pressure slightly elevated", detail: "Latest reading 128/82 mmHg.", recommendation: "Lifestyle measures can help."),
            Finding(severity: .info, category: .general, title: "Upcoming: Annual physical", detail: "Scheduled for March 20.", recommendation: nil)
        ]
        let review = makeReview(findings: findings, date: try makeFixedDate())
        let context = AIChatService.buildContext(review: review, profileSummary: "45-year-old male")

        for finding in findings {
            XCTAssertTrue(context.contains(finding.title), "Missing title: \(finding.title)")
            XCTAssertTrue(context.contains(finding.detail), "Missing detail: \(finding.detail)")
        }
        // Recommendation text is echoed for findings that have one.
        XCTAssertTrue(context.contains("Contact your doctor promptly."))
        XCTAssertTrue(context.contains("45-year-old male"))
    }

    func testBuildContextOmitsProfileLineWhenSummaryIsEmpty() throws {
        let review = makeReview(findings: [], date: try makeFixedDate())
        let context = AIChatService.buildContext(review: review, profileSummary: "")
        XCTAssertFalse(context.localizedCaseInsensitiveContains("Profile:"))
    }

    func testBuildContextReportsNoFindingsExplicitly() throws {
        let review = makeReview(findings: [], date: try makeFixedDate())
        let context = AIChatService.buildContext(review: review, profileSummary: "")
        XCTAssertTrue(context.contains("Findings: none"))
    }

    func testBuildContextOrderingIsDeterministicAcrossRepeatedCalls() throws {
        let findings = [
            Finding(severity: .critical, category: .labs, title: "Finding A", detail: "Detail A", recommendation: nil),
            Finding(severity: .attention, category: .vitals, title: "Finding B", detail: "Detail B", recommendation: nil),
            Finding(severity: .info, category: .general, title: "Finding C", detail: "Detail C", recommendation: nil)
        ]
        let review = makeReview(findings: findings, date: try makeFixedDate())

        let first = AIChatService.buildContext(review: review, profileSummary: "profile")
        let second = AIChatService.buildContext(review: review, profileSummary: "profile")
        XCTAssertEqual(first, second)

        // The findings must appear in the same order they were supplied.
        let indexA = try XCTUnwrap(first.range(of: "Finding A"))
        let indexB = try XCTUnwrap(first.range(of: "Finding B"))
        let indexC = try XCTUnwrap(first.range(of: "Finding C"))
        XCTAssertTrue(indexA.lowerBound < indexB.lowerBound)
        XCTAssertTrue(indexB.lowerBound < indexC.lowerBound)
    }

    // MARK: trimmedHistory

    private func message(_ role: AIChatMessage.Role, _ text: String) -> AIChatMessage {
        AIChatMessage(role: role, text: text)
    }

    func testTrimmedHistoryReturnsEmptyForEmptyInput() {
        XCTAssertEqual(AIChatService.trimmedHistory([], limit: 12), [])
    }

    func testTrimmedHistoryReturnsEmptyForAllAssistantInput() {
        let history = [
            message(.assistant, "Hello, how can I help?"),
            message(.assistant, "Still here if you have questions.")
        ]
        XCTAssertEqual(AIChatService.trimmedHistory(history, limit: 12), [])
    }

    func testTrimmedHistoryRespectsLimit() {
        let history = (0..<20).map { message(.user, "message \($0)") }
        let trimmed = AIChatService.trimmedHistory(history, limit: 5)
        XCTAssertEqual(trimmed.count, 5)
        XCTAssertEqual(trimmed.map(\.text), (15..<20).map { "message \($0)" })
    }

    func testTrimmedHistoryDropsLeadingAssistantMessageAfterTrimming() {
        // Limit of 4 lands the window mid-conversation, starting on an
        // assistant turn — that leading assistant message must be dropped
        // so the result starts with a user turn.
        let history = [
            message(.user, "u1"),
            message(.assistant, "a1"),
            message(.user, "u2"),
            message(.assistant, "a2"),
            message(.user, "u3"),
            message(.assistant, "a3")
        ]
        let trimmed = AIChatService.trimmedHistory(history, limit: 4)
        // Last 4 raw entries would be [u2, a2, u3, a3]; already starts with user.
        XCTAssertEqual(trimmed.map(\.text), ["u2", "a2", "u3", "a3"])

        let trimmedOdd = AIChatService.trimmedHistory(history, limit: 3)
        // Last 3 raw entries would be [a2, u3, a3] — leading assistant dropped.
        XCTAssertEqual(trimmedOdd.map(\.text), ["u3", "a3"])
    }

    func testTrimmedHistoryPreservesOrderWhenUnderLimit() {
        let history = [message(.user, "only message")]
        let trimmed = AIChatService.trimmedHistory(history, limit: 12)
        XCTAssertEqual(trimmed, history)
    }
}
