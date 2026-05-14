import XCTest
@testable import SchroSIM

final class BackendRegressionTests: XCTestCase {

    func testFoundryReferenceCircuitGaussianAndHybridParity() throws {
        let compiled = try makeReferenceFoundryCircuit()

        let gaussian = try Simulator.run(compiled)

        guard case .gaussian(let hybrid) = try HybridBackend.run(compiled, cutoff: 20) else {
            return XCTFail("Expected hybrid backend to resolve to gaussian path")
        }

        XCTAssertTrue(approxEqual(gaussian.mean, hybrid.mean, tol: 1e-12))
        XCTAssertTrue(LA.approxEqual(gaussian.cov, hybrid.cov, tol: 1e-12))

        // Reference value from examples/foundry_loss_map.json circuit.
        XCTAssertEqual(meanPhotonNumber(gaussian), 0.5647815555903229, accuracy: 1e-12)
    }

    func testRunAndMeasureIsDeterministicWithSeededRNG() throws {
        let c = try Circuit(modes: 1)
        c.squeeze(r: 0.4, on: 0)
        c.phase(theta: 0.2, on: 0)
        c.measureHomodyne(mode: 0, theta: 0.1)
        c.measureHeterodyne(mode: 0)

        var rngA: any RandomNumberGenerator = SeededGenerator(seed: 0x1234567890abcdef)
        let resultA = try Simulator.runAndMeasure(c, rng: &rngA)

        var rngB: any RandomNumberGenerator = SeededGenerator(seed: 0x1234567890abcdef)
        let resultB = try Simulator.runAndMeasure(c, rng: &rngB)

        XCTAssertEqual(resultA.measurements, resultB.measurements)
        XCTAssertTrue(approxEqual(resultA.finalState.mean, resultB.finalState.mean, tol: 1e-12))
        XCTAssertTrue(LA.approxEqual(resultA.finalState.cov, resultB.finalState.cov, tol: 1e-12))
    }

    func testHybridFockPathMatchesDirectFockBackend() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.fock(n: 2, mode: 0))
        c.phase(theta: 0.31, on: 0)
        c.displace(q: 0.6, p: -0.2, on: 0)

        let direct = try FockBackend.run(c, cutoff: 24).final

        guard case .fock(let hybrid) = try HybridBackend.run(c, cutoff: 24) else {
            return XCTFail("Expected hybrid backend to resolve to fock path")
        }

        XCTAssertEqual(hybrid.cutoff, direct.cutoff)
        XCTAssertEqual(hybrid.psi.count, direct.psi.count)
        for i in 0..<hybrid.psi.count {
            XCTAssertEqual(hybrid.psi[i].re, direct.psi[i].re, accuracy: 1e-12)
            XCTAssertEqual(hybrid.psi[i].im, direct.psi[i].im, accuracy: 1e-12)
        }
        XCTAssertEqual(hybrid.expectedPhotonNumber(), direct.expectedPhotonNumber(), accuracy: 1e-12)
    }

    private func makeReferenceFoundryCircuit() throws -> Circuit {
        let circuit = try Circuit(modes: 2)
        circuit.squeeze(r: 0.7, on: 0)
        circuit.phase(theta: 0.4, on: 0)
        circuit.beamSplitter(theta: 0.7853981634, 0, 1)
        circuit.displace(q: 0.3, p: -0.1, on: 1)

        let spec = FoundrySpec(
            name: "demo_foundry_v1",
            maxModes: 4,
            maxSqueezingR: 1.2,
            allowNonGaussian: true,
            allowMeasurements: true,
            modeLossEta: [0.93, 0.88],
            injectModeLoss: true
        )

        return try FoundryCompiler.compile(circuit, with: spec)
    }

    private func meanPhotonNumber(_ state: GaussianState) -> Double {
        var total = 0.0
        for mode in 0..<state.modes {
            let iq = 2 * mode
            let ip = iq + 1
            let q = state.mean[iq]
            let p = state.mean[ip]
            let vq = state.cov[iq][iq]
            let vp = state.cov[ip][ip]
            total += 0.5 * (q * q + p * p + vq + vp - 1.0)
        }
        return max(0.0, total)
    }

    private func approxEqual(_ a: [Double], _ b: [Double], tol: Double) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if abs(a[i] - b[i]) > tol { return false }
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
