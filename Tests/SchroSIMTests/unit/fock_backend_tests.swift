import XCTest
@testable import SchroSIM

final class FockBackendTests: XCTestCase {

    func testFockBackendPhaseKeepsNumberState() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.fock(n: 3, mode: 0))
        c.phase(theta: 0.7, on: 0)

        let r = try FockBackend.run(c, cutoff: 16)
        // Still |3> up to global phase -> photon number expectation ~3
        XCTAssert(abs(r.final.expectedPhotonNumber() - 3.0) < 1e-9)
    }

    func testFockBackendDisplacementRaisesPhotonNumber() throws {
        let c = try Circuit(modes: 1)
        c.displace(q: 1.0, p: 0.0, on: 0) // coherent-ish
        let r = try FockBackend.run(c, cutoff: 20)

        // For α=(q+i p)/sqrt(2), nbar ~ |α|^2 = q^2/2 = 0.5
        XCTAssert(r.final.expectedPhotonNumber() > 0.1)
    }
}