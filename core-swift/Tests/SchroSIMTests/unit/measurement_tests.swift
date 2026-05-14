import XCTest
@testable import SchroSIM

final class MeasurementTests: XCTestCase {

    func testHomodyneConditioningOnVacuum() throws {
        // 1 mode vacuum: V = 0.5 I
        let s = GaussianState.vacuum(modes: 1)

        // Measure q (theta=0) and condition on outcome 0
        let post = try GaussianMeasurement.conditionHomodyne(
            state: s, mode: 0, theta: 0.0, outcome: 0.0, vMeas: 0.0
        )

        // Expected: q variance -> 0, p variance stays 0.5
        let expected: Mat = [
            [0.0, 0.0],
            [0.0, 0.5]
        ]
        XCTAssertTrue(LA.approxEqual(post.cov, expected, tol: 1e-10))
    }

    func testHeterodyneConditioningOnVacuum() throws {
        // 1 mode vacuum: V = 0.5 I
        let s = GaussianState.vacuum(modes: 1)

        // Condition on (q,p) = (0,0) under heterodyne model (added noise 0.5 I)
        let post = try GaussianMeasurement.conditionHeterodyne(
            state: s, mode: 0, outcome: (0.0, 0.0)
        )

        // For vacuum: V' = 0.25 I
        let expected: Mat = [
            [0.25, 0.0],
            [0.0, 0.25]
        ]
        XCTAssertTrue(LA.approxEqual(post.cov, expected, tol: 1e-10))
    }

    func testCircuitMeasurementProducesEvents() throws {
        let c = try Circuit(modes: 1)
        c.squeeze(r: 0.4, on: 0)
        c.measureHomodyne(mode: 0, theta: 0.0)

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let res = try Simulator.runAndMeasure(c, rng: &rng)

        XCTAssertEqual(res.measurements.count, 1)
        XCTAssertEqual(res.measurements[0].mode, 0)
        XCTAssertEqual(res.measurements[0].values.count, 1)
    }
}