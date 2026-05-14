import XCTest
@testable import SchroSIM

final class FoundryTests: XCTestCase {

    func testFoundryInjectsModeLossMap() throws {
        let circuit = try Circuit(modes: 2)
        try circuit.append(.displace(q: 0.2, p: 0.0, mode: 0))

        let spec = FoundrySpec(
            name: "test_foundry",
            modeLossEta: [0.93, 1.0],
            injectModeLoss: true
        )

        let compiled = try FoundryCompiler.compile(circuit, with: spec)
        XCTAssertEqual(compiled.gates.count, circuit.gates.count + 1)

        guard case .loss(let eta, let mode) = compiled.gates.last else {
            return XCTFail("Expected loss gate injected by foundry map")
        }
        XCTAssertEqual(mode, 0)
        XCTAssertEqual(eta, 0.93, accuracy: 1e-12)
    }

    func testFoundryRejectsSqueezingAboveLimit() throws {
        let circuit = try Circuit(modes: 1)
        try circuit.append(.squeeze(r: 0.8, mode: 0))

        let spec = FoundrySpec(name: "bounded", maxSqueezingR: 0.5)
        XCTAssertThrowsError(try FoundryCompiler.validate(circuit, with: spec))
    }

    func testFoundryRejectsNonGaussianWhenDisallowed() throws {
        let circuit = try Circuit(modes: 1)
        try circuit.append(.injectNonGaussian(.fock(n: 1, mode: 0)))

        let spec = FoundrySpec(name: "gaussian_only", allowNonGaussian: false)
        XCTAssertThrowsError(try FoundryCompiler.validate(circuit, with: spec))
    }

    func testFoundryRejectsModeLossLengthMismatch() throws {
        let circuit = try Circuit(modes: 2)
        let spec = FoundrySpec(name: "bad_map", modeLossEta: [0.9])
        XCTAssertThrowsError(try FoundryCompiler.validate(circuit, with: spec))
    }
}
