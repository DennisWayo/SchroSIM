import Foundation

public enum HybridBackend {

    public enum Result {
        case gaussian(GaussianState)
        case fock(FockState)
    }

    public static func run(_ circuit: Circuit, cutoff: Int = 20) throws -> Result {
        if BackendRouting.requiresFockPath(circuit) {
            try BackendRouting.assertFockCompatible(circuit)
            let r = try FockBackend.run(circuit, cutoff: cutoff)
            return .fock(r.final)
        }

        // Gaussian path (includes effective GKP)
        let st = try Simulator.run(circuit)
        return .gaussian(st)
    }
}

extension HybridBackend: BackendCapabilities {
    public var supportsGaussian: Bool { true }
    public var supportsFock: Bool { true }
    public var supportsMeasurement: Bool { true }
    public var supportsFeedForward: Bool { false }
}
