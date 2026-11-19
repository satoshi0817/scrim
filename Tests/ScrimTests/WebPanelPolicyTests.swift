import XCTest
@testable import ScrimCore

final class WebPanelPolicyTests: XCTestCase {
    func testCalendarAuthAndDatedRoutesNeverBecomeLaunchURLs() {
        let root = URL(string: "https://calendar.notion.com/")!
        for path in ["auth?code=synthetic", "week/2020/1/1", "?date=2020-01-01"] {
            let url = URL(string: "https://calendar.notion.com/" + path)!
            XCTAssertEqual(WebPanelPolicy.launchURL(url), root)
            XCTAssertEqual(WebPanelPolicy.savedURL(url, previous: root), root)
        }
        XCTAssertFalse(WebPanelPolicy.canReturnToToday(URL(string: "https://calendar.notion.com/auth")!))
        XCTAssertTrue(WebPanelPolicy.canReturnToToday(root))
    }
    func testOtherWebPanelsKeepTheirNavigation() {
        let url = URL(string: "https://example.invalid/report?date=2020-01-01")!
        XCTAssertEqual(WebPanelPolicy.launchURL(url), url)
    }
    func testPeekPreferenceCanRestoreClickThroughBehavior() {
        XCTAssertFalse(VisibilityPlan(state: .peek).ignoresMouseEvents)
        XCTAssertTrue(VisibilityPlan(state: .peek, peekAllowsInteraction: false).ignoresMouseEvents)
        XCTAssertTrue(VisibilityPlan(state: .hidden).ignoresMouseEvents)
    }
}
