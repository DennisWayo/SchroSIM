import XCTest
@testable import SchroSIM

final class NonGaussianInjectionTests: XCTestCase {

    func testGKPEffectiveIsAcceptedByGaussianSimulator() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.gkp(delta: 0.2, mode: 0))

        XCTAssertNoThrow(try Simulator.run(c))
    }

    func testFockInjectionIsRejectedByGaussianSimulator() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.fock(n: 1, mode: 0))

        XCTAssertThrowsError(try Simulator.run(c))
    }
}