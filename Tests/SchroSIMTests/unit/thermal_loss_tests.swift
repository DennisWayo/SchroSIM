import XCTest
@testable import SchroSIM

final class ThermalLossTests: XCTestCase {

    /// Thermal loss must reduce exactly to pure loss when n_th = 0
    func testThermalLossReducesToPureLossWhenNThZero() throws {
        let eta = 0.42
        let nTh = 0.0

        // Vacuum state
        var psi = GaussianState.vacuum(modes: 1)

        // Apply a displacement so we also test mean scaling
        let disp = CVGate(S: LA.eye(2), d: [1.5, -0.5])
        psi = SymplecticEvolution.apply(disp, to: psi)

        let outThermal = try GaussianChannels.applyThermalLoss(
            psi,
            mode: 0,
            eta: eta,
            nTh: nTh
        )

        let outLoss = try GaussianChannels.applyLoss(
            psi,
            mode: 0,
            eta: eta
        )

        // Covariances must match exactly
        XCTAssertTrue(
            LA.approxEqual(outThermal.cov, outLoss.cov, tol: 1e-12),
            "Thermal loss with nTh=0 must reduce to pure loss"
        )

        // Means must scale identically
        XCTAssertEqual(outThermal.mean[0], outLoss.mean[0], accuracy: 1e-12)
        XCTAssertEqual(outThermal.mean[1], outLoss.mean[1], accuracy: 1e-12)
    }

    /// Thermal loss must add excess noise compared to vacuum loss
    func testThermalLossAddsMoreNoiseThanVacuumLoss() throws {
        let eta = 0.60
        let nTh = 2.0

        let psi = GaussianState.vacuum(modes: 1)
        let out = try GaussianChannels.applyThermalLoss(
            psi,
            mode: 0,
            eta: eta,
            nTh: nTh
        )

        // Mean must remain zero for vacuum input
        XCTAssertTrue(
            out.mean.allSatisfy { abs($0) < 1e-12 },
            "Vacuum mean must remain zero under thermal loss"
        )

        // Expected covariance:
        // V = eta * (1/2) + (1 - eta) * (nTh + 1/2)
        let expected = eta * 0.5 + (1.0 - eta) * (nTh + 0.5)

        XCTAssertEqual(out.cov[0][0], expected, accuracy: 1e-12)
        XCTAssertEqual(out.cov[1][1], expected, accuracy: 1e-12)
    }

    /// Thermal loss must integrate cleanly with the circuit + simulator
    func testCircuitThermalLossRuns() throws {
        let c = try Circuit(modes: 1)

        c.displace(q: 1.0, p: 0.0, on: 0)
        c.thermalLoss(eta: 0.8, nTh: 1.0, on: 0)

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let result = try Simulator.runAndMeasure(c, rng: &rng)

        XCTAssertEqual(result.measurements.count, 0)
        XCTAssertEqual(result.finalState.modes, 1)
    }
}