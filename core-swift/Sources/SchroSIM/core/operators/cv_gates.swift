import Foundation

public struct CVGate: Sendable {
    /// Symplectic matrix S (2n x 2n)
    public let S: Mat

    /// Displacement vector d (length 2n)
    public let d: Vec

    public init(S: Mat, d: Vec) {
        precondition(!S.isEmpty && S.count == S[0].count)
        precondition(S.count == d.count)
        self.S = S
        self.d = d
    }

    public static func identity(modes: Int) -> CVGate {
        let dim = 2 * modes
        return CVGate(S: LA.eye(dim), d: Array(repeating: 0.0, count: dim))
    }

    /// Single-mode phase shift by angle θ: (q,p) -> (q cosθ - p sinθ, q sinθ + p cosθ)
    public static func phaseShift(theta: Double, mode: Int, modes: Int) -> CVGate {
        precondition(mode >= 0 && mode < modes)
        let dim = 2 * modes
        var S = LA.eye(dim)
        let c = cos(theta)
        let s = sin(theta)

        let i = 2 * mode
        // block [[c, -s],[s, c]]
        S[i][i] = c
        S[i][i+1] = -s
        S[i+1][i] = s
        S[i+1][i+1] = c

        return CVGate(S: S, d: Array(repeating: 0.0, count: dim))
    }

    /// Single-mode squeezing with parameter r:
    /// q -> e^{-r} q, p -> e^{+r} p
    public static func squeeze(r: Double, mode: Int, modes: Int) -> CVGate {
        precondition(mode >= 0 && mode < modes)
        let dim = 2 * modes
        var S = LA.eye(dim)
        let i = 2 * mode
        S[i][i] = exp(-r)
        S[i+1][i+1] = exp(r)
        return CVGate(S: S, d: Array(repeating: 0.0, count: dim))
    }

    /// 50:50 beamsplitter by angle θ between modes a and b in (q,p) ordering.
    /// Uses standard passive linear optics transform applied identically to q and p subspaces.
    public static func beamSplitter(theta: Double, modeA: Int, modeB: Int, modes: Int) -> CVGate {
        precondition(modeA != modeB)
        precondition(modeA >= 0 && modeA < modes)
        precondition(modeB >= 0 && modeB < modes)

        let dim = 2 * modes
        var S = LA.eye(dim)

        let c = cos(theta)
        let s = sin(theta)

        let a = 2 * modeA
        let b = 2 * modeB

        // q-subspace mixing: q_a' = c q_a - s q_b ; q_b' = s q_a + c q_b
        S[a][a] = c
        S[a][b] = -s
        S[b][a] = s
        S[b][b] = c

        // p-subspace mixing: same
        S[a+1][a+1] = c
        S[a+1][b+1] = -s
        S[b+1][a+1] = s
        S[b+1][b+1] = c

        return CVGate(S: S, d: Array(repeating: 0.0, count: dim))
    }
}