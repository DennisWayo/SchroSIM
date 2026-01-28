import Foundation

/// Placeholder for non-Gaussian injections (Fock, cat, GKP, ...).
/// This is IR-level only for now; Gaussian backend will refuse at runtime.
public enum NonGaussianState: Sendable, Equatable {
    case fock(n: Int, mode: Int)
    case cat(alpha: Double, mode: Int)
    case gkp(delta: Double, mode: Int)

    /// Convenience for circuit-level validation / bookkeeping.
    public var modes: Int { 1 }
}