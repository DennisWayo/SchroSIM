import XCTest
@testable import SchroSIM

final class CompilerIRTests: XCTestCase {

    func testCircuitRunsAndPreservesSymplecticStructureForGaussianOps() throws {
        let c = try Circuit(modes: 2)
        c.squeeze(r: 0.7, on: 0)
        c.phase(theta: 0.3, on: 0)
        c.beamSplitter(theta: .pi/4, 0, 1)
        c.displace(q: 0.2, p: -0.1, on: 1)

        let out = try Simulator.run(c)

        // Basic shape checks
        XCTAssertEqual(out.mean.count, 4)
        XCTAssertEqual(out.cov.count, 4)
        XCTAssertEqual(out.cov[0].count, 4)

        // Covariance must remain symmetric under ideal symplectic evolution
        XCTAssertTrue(LA.approxEqual(out.cov, LA.transpose(out.cov), tol: 1e-10))
    }
}