import Foundation

public enum HybridBackend {

    public enum Result {
        case gaussian(GaussianState)
        case fock(FockState)
    }

    public static func run(_ circuit: Circuit, cutoff: Int = 20) throws -> Result {

        // Decide backend
        var needsFock = false

        for g in circuit.gates {
            if case .injectNonGaussian(let ng) = g {
                switch ng {
                case .fock, .cat:
                    needsFock = true
                case .gkp:
                    break // stays on Gaussian-effective path
                }
            }
        }

        if needsFock {
            let r = try FockBackend.run(circuit, cutoff: cutoff)
            return .fock(r.final)
        }

        // Gaussian path (includes effective GKP)
        let st = try Simulator.run(circuit)
        return .gaussian(st)
    }
}