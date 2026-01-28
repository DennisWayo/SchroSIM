import XCTest
@testable import SchroSIM

final class GKPEffectiveTests: XCTestCase {

    func testGKPEffectiveInflatesCovariance() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.gkp(delta: 0.2, mode: 0))

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let res = try Simulator.runAndMeasure(c, rng: &rng)

        // Vacuum cov is 0.5 I. After injection, should be > 0.5 on both quadratures.
        XCTAssert(res.finalState.cov[0][0] > 0.5)
        XCTAssert(res.finalState.cov[1][1] > 0.5)
    }
}