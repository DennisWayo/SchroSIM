import Foundation

public enum FockBackendError: Error, CustomStringConvertible {
    case onlySingleModeSupported
    case unsupportedGate(Gate)

    public var description: String {
        switch self {
        case .onlySingleModeSupported:
            return "Fock backend MVP supports single-mode circuits only."
        case .unsupportedGate(let g):
            return "Gate not supported in Fock backend MVP: \(g)"
        }
    }
}

public enum FockBackend {

    public struct Result: Sendable {
        public let final: FockState
    }

    public static func run(
        _ circuit: Circuit,
        cutoff: Int
    ) throws -> Result {

        guard circuit.modes == 1 else {
            throw FockBackendError.onlySingleModeSupported
        }

        var st = FockState.vacuum(cutoff: cutoff)

        for g in circuit.gates {
            switch g {

            case .phase(let theta, _):
                let U = FockOps.phase(theta: theta, cutoff: cutoff)
                st = FockOps.apply(U, to: st)

            case .displace(let q, let p, _):
                // Map (q,p) to α. Convention: q = sqrt(2) Re(α), p = sqrt(2) Im(α)
                // => α = (q + i p)/sqrt(2)
                let alpha = Complex(q / sqrt(2.0), p / sqrt(2.0))
                let U = FockOps.displace(alpha: alpha, cutoff: cutoff)
                st = FockOps.apply(U, to: st)

            case .injectNonGaussian(let ng):
                switch ng {
                case .fock(let n, _):
                    st = FockStates.fock(n: n, cutoff: cutoff)
                case .cat(let alpha, _):
                    st = FockStates.cat(alpha: alpha, cutoff: cutoff, even: true)
                case .gkp:
                    // True GKP is not Fock-MVP; let C2 handle effective-GKP in Gaussian backend
                    throw FockBackendError.unsupportedGate(g)
                }

            default:
                throw FockBackendError.unsupportedGate(g)
            }
        }

        return Result(final: st)
    }
}