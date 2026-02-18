import XCTest
@testable import Conductor

final class DayReviewServiceTests: XCTestCase {
    @MainActor
    func test_dayReview_autoOpenOnlyOncePerDay() throws {
        let db = try Database(inMemory: true)
        let service = DayReviewService(database: db, todayProvider: { "2026-02-11" })

        XCTAssertTrue(service.shouldAutoShowOnLaunch())
        service.markShownToday()
        XCTAssertFalse(service.shouldAutoShowOnLaunch())

        let tomorrow = DayReviewService(database: db, todayProvider: { "2026-02-12" })
        XCTAssertTrue(tomorrow.shouldAutoShowOnLaunch())
    }
}
