import XCTest
@testable import SchroSIM

final class NonGaussianInjectionTests: XCTestCase {

    func testInjectionIsRecognizedButNotSimulated() throws {
        let c = try Circuit(modes: 1)
        c.inject(.gkp(delta: 0.2, mode: 0))

        XCTAssertThrowsError(try Simulator.run(c))
    }
}