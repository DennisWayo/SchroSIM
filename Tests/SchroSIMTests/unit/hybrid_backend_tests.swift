import XCTest
@testable import SchroSIM

final class HybridBackendTests: XCTestCase {

    func testHybridChoosesGaussianForPureGaussianCircuit() throws {
        let c = try Circuit(modes: 1)
        c.displace(q: 1.0, p: 0.0, on: 0)
        let r = try HybridBackend.run(c, cutoff: 16)
        switch r {
        case .gaussian: XCTAssertTrue(true)
        case .fock: XCTFail("Should not choose Fock for Gaussian-only circuit.")
        }
    }

    func testHybridChoosesFockForFockInjection() throws {
        let c = try Circuit(modes: 1)
        c.injectNonGaussian(.fock(n: 2, mode: 0))
        let r = try HybridBackend.run(c, cutoff: 16)
        switch r {
        case .fock(let st):
            XCTAssert(abs(st.expectedPhotonNumber() - 2.0) < 1e-9)
        case .gaussian:
            XCTFail("Should choose Fock backend for Fock injection.")
        }
    }
}