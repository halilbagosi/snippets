import XCTest
@testable import Snippets

final class AppLinksTests: XCTestCase {
    func test_feedbackEmail_addressesFeedbackWithTheVersionInTheSubject() throws {
        let url = AppLinks.feedbackEmail(version: "1.4")
        XCTAssertEqual(url.absoluteString, "mailto:snippets.feedback@halilbagosi.com?subject=Snippets%20Feedback%20(version%201.4)")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value, "Snippets Feedback (version 1.4)")
    }

    func test_feedbackEmail_defaultsToTheAppVersion() throws {
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(AppLinks.feedbackEmail(), AppLinks.feedbackEmail(version: version))
    }
}
