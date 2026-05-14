import XCTest
@testable import SchroSIM

final class FeedForwardTests: XCTestCase {

    func testClassicalControlConditionFalseSkipsApply() throws {
        let conditioned = try Circuit(modes: 1)
        conditioned.displace(q: 0.3, p: 0.0, on: 0)
        conditioned.measureHomodyne(mode: 0, theta: 0.0)
        try conditioned.append(
            .classicalControl(
                on: 0,
                condition: ClassicalCondition(valueIndex: 0, comparator: .gt, threshold: 1e9),
                apply: .phase(theta: 0.7, mode: 0)
            )
        )

        let baseline = try Circuit(modes: 1)
        baseline.displace(q: 0.3, p: 0.0, on: 0)
        baseline.measureHomodyne(mode: 0, theta: 0.0)

        var rngA: any RandomNumberGenerator = SeededGenerator(seed: 1234)
        let resultA = try Simulator.runAndMeasure(conditioned, rng: &rngA)

        var rngB: any RandomNumberGenerator = SeededGenerator(seed: 1234)
        let resultB = try Simulator.runAndMeasure(baseline, rng: &rngB)

        XCTAssertTrue(approxEqual(resultA.finalState.mean, resultB.finalState.mean, tol: 1e-12))
        XCTAssertTrue(LA.approxEqual(resultA.finalState.cov, resultB.finalState.cov, tol: 1e-12))
    }

    func testClassicalControlConditionTrueApplies() throws {
        let conditioned = try Circuit(modes: 1)
        conditioned.displace(q: 0.3, p: 0.0, on: 0)
        conditioned.measureHomodyne(mode: 0, theta: 0.0)
        try conditioned.append(
            .classicalControl(
                on: 0,
                condition: ClassicalCondition(valueIndex: 0, comparator: .gt, threshold: -1e9),
                apply: .phase(theta: 0.7, mode: 0)
            )
        )

        let baseline = try Circuit(modes: 1)
        baseline.displace(q: 0.3, p: 0.0, on: 0)
        baseline.measureHomodyne(mode: 0, theta: 0.0)
        baseline.phase(theta: 0.7, on: 0)

        var rngA: any RandomNumberGenerator = SeededGenerator(seed: 5678)
        let resultA = try Simulator.runAndMeasure(conditioned, rng: &rngA)

        var rngB: any RandomNumberGenerator = SeededGenerator(seed: 5678)
        let resultB = try Simulator.runAndMeasure(baseline, rng: &rngB)

        XCTAssertTrue(approxEqual(resultA.finalState.mean, resultB.finalState.mean, tol: 1e-12))
        XCTAssertTrue(LA.approxEqual(resultA.finalState.cov, resultB.finalState.cov, tol: 1e-12))
    }

    func testClassicalControlValueIndexOutOfRangeThrows() throws {
        let circuit = try Circuit(modes: 1)
        circuit.measureHeterodyne(mode: 0)
        try circuit.append(
            .classicalControl(
                on: 0,
                condition: ClassicalCondition(valueIndex: 2, comparator: .gt, threshold: 0.0),
                apply: .phase(theta: 0.4, mode: 0)
            )
        )

        var rng: any RandomNumberGenerator = SeededGenerator(seed: 99)
        XCTAssertThrowsError(try Simulator.runAndMeasure(circuit, rng: &rng))
    }

    func testFeedbackDisplaceUsesMeasurementValue() throws {
        let circuit = try Circuit(modes: 1)
        circuit.displace(q: 0.45, p: 0.0, on: 0)
        circuit.measureHomodyne(mode: 0, theta: 0.0)
        try circuit.append(
            .feedbackDisplace(
                on: 0,
                valueIndex: 0,
                gainQ: -1.0,
                gainP: 0.0,
                biasQ: 0.0,
                biasP: 0.0,
                mode: 0
            )
        )

        var rng: any RandomNumberGenerator = SeededGenerator(seed: 8080)
        let result = try Simulator.runAndMeasure(circuit, rng: &rng)
        XCTAssertEqual(result.measurements.count, 1)
        XCTAssertEqual(result.finalState.mean[0], 0.0, accuracy: 1e-10)
    }

    func testFeedbackDisplaceValueIndexOutOfRangeThrows() throws {
        let circuit = try Circuit(modes: 1)
        circuit.measureHeterodyne(mode: 0)
        try circuit.append(
            .feedbackDisplace(
                on: 0,
                valueIndex: 2,
                gainQ: -1.0,
                gainP: 0.0,
                biasQ: 0.0,
                biasP: 0.0,
                mode: 0
            )
        )

        var rng: any RandomNumberGenerator = SeededGenerator(seed: 123)
        XCTAssertThrowsError(try Simulator.runAndMeasure(circuit, rng: &rng))
    }

    func testGKPDecodeDisplaceAppliesNearestLatticeCorrection() throws {
        let circuit = try Circuit(modes: 1)
        circuit.displace(q: 4.0, p: 0.0, on: 0)
        circuit.measureHomodyne(mode: 0, theta: 0.0)
        try circuit.append(
            .gkpDecodeDisplace(
                on: 0,
                valueIndex: 0,
                latticeSpacing: sqrt(Double.pi),
                targetLatticeIndex: 0,
                gainQ: 1.0,
                gainP: 0.0,
                biasQ: 0.0,
                biasP: 0.0,
                mode: 0
            )
        )

        var rng: any RandomNumberGenerator = SeededGenerator(seed: 4242)
        let result = try Simulator.runAndMeasure(circuit, rng: &rng)
        XCTAssertEqual(result.measurements.count, 1)

        let syndrome = result.measurements[0].values[0]
        let decoded = GKPNearestLatticeDecoder.decode(
            syndromeValue: syndrome,
            latticeSpacing: sqrt(Double.pi),
            targetLatticeIndex: 0
        )
        XCTAssertFalse(decoded.logicalPass)
        XCTAssertEqual(result.finalState.mean[0], syndrome + decoded.correction, accuracy: 1e-10)
    }

    func testGKPDecodeDisplaceValueIndexOutOfRangeThrows() throws {
        let circuit = try Circuit(modes: 1)
        circuit.measureHeterodyne(mode: 0)
        try circuit.append(
            .gkpDecodeDisplace(
                on: 0,
                valueIndex: 3,
                latticeSpacing: sqrt(Double.pi),
                targetLatticeIndex: 0,
                gainQ: 1.0,
                gainP: 0.0,
                biasQ: 0.0,
                biasP: 0.0,
                mode: 0
            )
        )

        var rng: any RandomNumberGenerator = SeededGenerator(seed: 2)
        XCTAssertThrowsError(try Simulator.runAndMeasure(circuit, rng: &rng))
    }

    private func approxEqual(_ a: [Double], _ b: [Double], tol: Double) -> Bool {
        guard a.count == b.count else { return false }
        for idx in 0..<a.count {
            if abs(a[idx] - b[idx]) > tol { return false }
        }
        return true
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
