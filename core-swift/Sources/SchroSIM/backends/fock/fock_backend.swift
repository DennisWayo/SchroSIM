import Foundation

// --------------------------------------------------
// MARK: - Errors
// --------------------------------------------------

public enum FockBackendError: Error, CustomStringConvertible {
    case onlySingleModeSupported
    case unsupportedGate(String)

    public var description: String {
        switch self {
        case .onlySingleModeSupported:
            return "Fock backend supports only single-mode circuits"
        case .unsupportedGate(let msg):
            return msg
        }
    }
}

// --------------------------------------------------
// MARK: - Backend
// --------------------------------------------------

public enum FockBackend {

    public struct Result: Sendable {
        public let final: FockState
    }

    public struct TraceFrame: Sendable {
        public let gateIndex: Int
        public let gate: Gate
        public let meanPhotonNumber: Double
        public let frameLatencyMs: Double
    }

    public struct TraceResult: Sendable {
        public let final: FockState
        public let frames: [TraceFrame]
    }

    public static func run(
        _ circuit: Circuit,
        cutoff: Int
    ) throws -> Result {
        try runStreaming(circuit, cutoff: cutoff) { _ in }
    }

    public static func runTrace(
        _ circuit: Circuit,
        cutoff: Int
    ) throws -> TraceResult {
        var frames: [TraceFrame] = []
        let result = try runStreaming(circuit, cutoff: cutoff) { frame in
            frames.append(frame)
        }
        return TraceResult(final: result.final, frames: frames)
    }

    public static func runStreaming(
        _ circuit: Circuit,
        cutoff: Int,
        onFrame: (TraceFrame) -> Void
    ) throws -> Result {

        guard circuit.modes == 1 else {
            throw FockBackendError.onlySingleModeSupported
        }

        var st = FockState.vacuum(cutoff: cutoff)

        for (idx, g) in circuit.gates.enumerated() {
            let frameStart = CFAbsoluteTimeGetCurrent()
            switch g {

            case .phase(let theta, _):
                let U = FockOps.phase(theta: theta, cutoff: cutoff)
                st = FockOps.apply(U, to: st)

            case .displace(let q, let p, _):
                // q = sqrt(2) Re(α), p = sqrt(2) Im(α)
                let alpha = Complex(q / sqrt(2.0), p / sqrt(2.0))
                let U = FockOps.displace(alpha: alpha, cutoff: cutoff)
                st = FockOps.apply(U, to: st)

            case .injectNonGaussian(let ng):
                switch ng {
                case .fock(let n, let mode):
                    guard mode == 0 else {
                        throw FockBackendError.unsupportedGate(
                            "Fock injection mode \(mode) is invalid for single-mode Fock backend"
                        )
                    }
                    st = FockStates.fock(n: n, cutoff: cutoff)

                case .cat(let alpha, let mode):
                    guard mode == 0 else {
                        throw FockBackendError.unsupportedGate(
                            "Cat injection mode \(mode) is invalid for single-mode Fock backend"
                        )
                    }
                    st = FockStates.cat(alpha: alpha, cutoff: cutoff, even: true)

                case .gkp:
                    // GKP handled in Gaussian backend (effective)
                    throw FockBackendError.unsupportedGate(
                        "GKP states are not supported by the Fock backend"
                    )
                }

            default:
                throw FockBackendError.unsupportedGate(
                    "Unsupported gate in Fock backend: \(g)"
                )
            }

            onFrame(
                TraceFrame(
                    gateIndex: idx,
                    gate: g,
                    meanPhotonNumber: st.expectedPhotonNumber(),
                    frameLatencyMs: max(0.0, (CFAbsoluteTimeGetCurrent() - frameStart) * 1000.0)
                )
            )
        }

        return Result(final: st)
    }
}

// --------------------------------------------------
// MARK: - Backend Capabilities
// --------------------------------------------------

extension FockBackend: BackendCapabilities {
    public var supportsGaussian: Bool { false }
    public var supportsFock: Bool { true }
    public var supportsMeasurement: Bool { false }
    public var supportsFeedForward: Bool { false }
}
