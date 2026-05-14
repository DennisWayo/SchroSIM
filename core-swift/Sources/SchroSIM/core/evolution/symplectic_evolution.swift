import Foundation

public enum SymplecticEvolution {
    /// Apply affine symplectic transform:
    /// mean' = S mean + d
    /// cov'  = S cov S^T
    public static func apply(_ gate: CVGate, to state: GaussianState) -> GaussianState {
        let dim = 2 * state.modes
        precondition(gate.S.count == dim && gate.d.count == dim)

        let newMean = LA.add(LA.matvec(gate.S, state.mean), gate.d)
        let Scov = LA.matmul(gate.S, state.cov)
        let newCov = LA.matmul(Scov, LA.transpose(gate.S))

        var out = state
        out.mean = newMean
        out.cov = newCov
        return out
    }

    /// Validate symplectic condition: S Ω S^T = Ω
    public static func isSymplectic(_ S: Mat, modes: Int, tol: Double = 1e-8) -> Bool {
        let omega = LA.symplecticForm(modes: modes)
        let left = LA.matmul(LA.matmul(S, omega), LA.transpose(S))
        return LA.approxEqual(left, omega, tol: tol)
    }
}
