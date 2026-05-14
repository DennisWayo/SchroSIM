import XCTest
@testable import SchroSIM

final class ComputeBackendTests: XCTestCase {

    func testResolverNoLongerUsesPhase1Fallback() {
        let workload = ComputeWorkloadProfile(
            modes: 8,
            gateCount: 256,
            includesFockPath: false,
            includesMeasurements: false
        )
        let result = ComputeBackendResolver.resolve(requested: .metal, workload: workload)
        XCTAssertNotEqual(result.fallbackReason, "metal_path_not_implemented_phase1")

        if ComputeBackendResolver.metalExecutionAvailable {
            XCTAssertEqual(result.used, .metal)
            XCTAssertNil(result.fallbackReason)
        } else {
            XCTAssertEqual(result.used, .cpu)
            XCTAssertNotNil(result.fallbackReason)
        }
    }

    func testExecutionContextRestoresPreviousBackend() {
        let previous = ComputeExecutionContext.currentBackend
        let observed = ComputeExecutionContext.withBackend(.metal) {
            ComputeExecutionContext.currentBackend
        }
        XCTAssertEqual(observed, .metal)
        XCTAssertEqual(ComputeExecutionContext.currentBackend, previous)
    }
}
