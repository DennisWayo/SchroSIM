import Foundation

public struct GaussianState: Sendable {
    /// Number of modes (n). Phase-space dimension is 2n.
    public let modes: Int

    /// Mean vector in (q1,p1,q2,p2,...) ordering. Length 2n.
    public var mean: Vec

    /// Covariance matrix (2n x 2n). Convention: V_ij = 1/2 <{R_i - <R_i>, R_j - <R_j>}>
    public var cov: Mat

    public init(modes: Int, mean: Vec? = nil, cov: Mat? = nil) {
        precondition(modes > 0)
        self.modes = modes
        let dim = 2 * modes

        self.mean = mean ?? Array(repeating: 0.0, count: dim)

        if let cov = cov {
            precondition(cov.count == dim && cov.first?.count == dim)
            self.cov = cov
        } else {
            // Vacuum: V = (1/2) I
            var v = LA.eye(dim)
            for i in 0..<dim { v[i][i] *= 0.5 }
            self.cov = v
        }

        precondition(self.mean.count == dim)
    }

    public static func vacuum(modes: Int) -> GaussianState {
        GaussianState(modes: modes)
    }
}