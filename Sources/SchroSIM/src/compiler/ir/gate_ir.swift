import Foundation

/// IR-level gate (logical description).
/// This stays backend-agnostic and is lowered later into concrete operators (e.g., CVGate).
public enum Gate: Sendable, Equatable {
    case phase(theta: Double, mode: Int)
    case squeeze(r: Double, mode: Int)
    case beamSplitter(theta: Double, modeA: Int, modeB: Int)

    /// Phase-space displacement (q, p) on one mode.
    /// Convention: mean' = mean + d, with d inserted into the (q,p) slots.
    case displace(q: Double, p: Double, mode: Int)

    /// Placeholder for future channels/noise in IR (loss, thermal, dephasing, etc.)
    /// We’ll keep the type here but not implement it yet.
    case noisePlaceholder(label: String)
    case loss(eta: Double, mode: Int)   // pure-loss channel with transmissivity eta in [0,1]
    case thermalLoss(eta: Double, nTh: Double, mode: Int) // nTh >= 0, eta in [0,1]
    case injectNonGaussian(NonGaussianState)

    // Measurements
    case measureHomodyne(mode: Int, theta: Double)   // measures x_theta = q cosθ + p sinθ
    case measureHeterodyne(mode: Int)                // measures (q,p) jointly (modeled with added vacuum noise)

}

public enum IRValidationError: Error, CustomStringConvertible {
    case invalidMode(Int)
    case invalidPair(Int, Int)
    case invalidModesCount(Int)
    case invalidParameter(String)

    public var description: String {
        switch self {
        case .invalidMode(let m): return "Invalid mode index: \(m)"
        case .invalidPair(let a, let b): return "Invalid mode pair: (\(a), \(b))"
        case .invalidModesCount(let n): return "Invalid modes count: \(n)"
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        }
    }
}