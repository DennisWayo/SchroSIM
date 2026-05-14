import XCTest
@testable import SchroSIM

final class StateTests: XCTestCase {

    func testVacuumCovarianceIsHalfIdentity() {
        let s = GaussianState.vacuum(modes: 2)
        let dim = 4
        var expected = LA.eye(dim)
        for i in 0..<dim { expected[i][i] *= 0.5 }
        XCTAssertTrue(LA.approxEqual(s.cov, expected, tol: 1e-12))
        XCTAssertEqual(s.mean, [0,0,0,0])
    }

    func testSqueezingTransformsCovariance() {
        let modes = 1
        let vac = GaussianState.vacuum(modes: modes)
        let gate = CVGate.squeeze(r: 1.0, mode: 0, modes: modes)

        XCTAssertTrue(SymplecticEvolution.isSymplectic(gate.S, modes: modes))

        let out = SymplecticEvolution.apply(gate, to: vac)

        // Vacuum V = (1/2)I. After squeezing:
        // Vqq = (1/2) e^{-2r}, Vpp = (1/2) e^{+2r}
        let r = 1.0
        let expected: Mat = [
            [0.5 * exp(-2*r), 0.0],
            [0.0, 0.5 * exp( 2*r)]
        ]
        XCTAssertTrue(LA.approxEqual(out.cov, expected, tol: 1e-10))
    }

    func testBeamSplitterIsSymplectic() {
        let modes = 2
        let bs = CVGate.beamSplitter(theta: .pi/4, modeA: 0, modeB: 1, modes: modes)
        XCTAssertTrue(SymplecticEvolution.isSymplectic(bs.S, modes: modes))
    }
}