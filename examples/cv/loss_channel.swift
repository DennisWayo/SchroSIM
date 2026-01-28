import Foundation

/// Gaussian channels acting directly on a `GaussianState`.
public enum GaussianChannels {

    /// Pure-loss (attenuation) channel with transmissivity `eta` on a single mode.
    ///
    /// Physics convention:
    ///   d' = K d
    ///   V' = K V Kᵀ + (1 - eta) * I / 2
    ///
    /// where K rescales the (q,p) quadratures of the target mode by sqrt(eta).
    public static func applyLoss(
        _ state: GaussianState,
        mode: Int,
        eta: Double
    ) throws -> GaussianState {

        // --- Validation ---
        guard (0.0...1.0).contains(eta) else {
            throw SimulatorError.invalidLowering(
                "Loss channel requires eta ∈ [0,1], got \(eta)"
            )
        }
        guard mode >= 0 && mode < state.modes else {
            throw SimulatorError.invalidLowering(
                "Loss channel mode out of range: \(mode), modes = \(state.modes)"
            )
        }

        let n = 2 * state.modes
        let i = 2 * mode
        let s = sqrt(eta)

        // --- Symplectic attenuation matrix K ---
        var K = LA.eye(n)
        K[i][i] = s
        K[i + 1][i + 1] = s

        let KT = LA.transpose(K)

        // --- Covariance update: V' = K V Kᵀ ---
        let KV = LA.matmul(K, state.cov)
        let Vscaled = LA.matmul(KV, KT)

        // --- Vacuum noise contribution ---
        var N = LA.zeros(n, n)
        let noise = (1.0 - eta) * 0.5
        N[i][i] = noise
        N[i + 1][i + 1] = noise

        let Vout = LA.add(Vscaled, N)

        // --- Mean update: d' = K d ---
        let dout = LA.matvec(K, state.mean)

        return GaussianState(
            modes: state.modes,
            mean: dout,
            cov: Vout
        )
    }
}