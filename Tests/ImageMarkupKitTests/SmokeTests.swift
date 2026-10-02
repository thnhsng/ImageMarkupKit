import XCTest
@testable import ImageMarkupKit

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(ImageMarkupKit.version.isEmpty)
    }
}
