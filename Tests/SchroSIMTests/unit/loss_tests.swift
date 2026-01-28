import XCTest
@testable import SchroSIM

final class LossTests: XCTestCase {

    func testLossOnVacuumLeavesVacuum() throws {
        let eta = 0.37
        let psi = GaussianState.vacuum(modes: 1)

        let out = try GaussianChannels.applyLoss(psi, mode: 0, eta: eta)

        // Vacuum mean is zero
        XCTAssertTrue(out.mean.allSatisfy { abs($0) < 1e-12 })

        // Vacuum covariance is (1/2) I, and loss channel should keep it vacuum when env is vacuum
        XCTAssertTrue(LA.approxEqual(out.cov, psi.cov, tol: 1e-10))
    }

    func testLossScalesDisplacementMeanBySqrtEta() throws {
        let eta = 0.25
        var psi = GaussianState.vacuum(modes: 1)

        // Apply displacement by hand via gate lowering path:
        // mean' = mean + d
        psi = SymplecticEvolution.apply(
            CVGate(S: LA.eye(2), d: [2.0, -4.0]),
            to: psi
        )

        let out = try GaussianChannels.applyLoss(psi, mode: 0, eta: eta)

        let s = sqrt(eta)
        XCTAssertEqual(out.mean[0], s * psi.mean[0], accuracy: 1e-12)
        XCTAssertEqual(out.mean[1], s * psi.mean[1], accuracy: 1e-12)
    }

    func testLossCrossCorrelationScalesBySqrtEta() throws {
        // Two-mode state: create a correlated covariance (artificial but valid for scaling test).
        // We just test the linear-algebraic rule that cross-cov terms involving the lossy mode scale by sqrt(eta).
        let eta = 0.64
        let s = sqrt(eta)

        var psi = GaussianState.vacuum(modes: 2)

        // Inject a cross-correlation between mode0.q and mode1.q
        var V = psi.cov
        // indices: mode0.q=0, mode0.p=1, mode1.q=2, mode1.p=3
        V[0][2] = 0.10
        V[2][0] = 0.10
        psi = GaussianState(modes: 2, mean: psi.mean, cov: V)

        let out = try GaussianChannels.applyLoss(psi, mode: 0, eta: eta)

        // Cross term (0,2) should scale by sqrt(eta)
        XCTAssertEqual(out.cov[0][2], s * psi.cov[0][2], accuracy: 1e-12)
        XCTAssertEqual(out.cov[2][0], s * psi.cov[2][0], accuracy: 1e-12)
    }

    func testCircuitLossRunsAndProducesNoMeasurementEvents() throws {
        let c = try Circuit(modes: 1)
        c.displace(q: 1.0, p: 0.0, on: 0)
        c.loss(eta: 0.8, on: 0)

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let res = try Simulator.runAndMeasure(c, rng: &rng)

        XCTAssertEqual(res.measurements.count, 0)
        XCTAssertEqual(res.finalState.modes, 1)
    }
}