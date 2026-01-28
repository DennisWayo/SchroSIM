import Foundation

/// Gaussian channels acting directly on a `GaussianState`.
public enum GaussianChannels {

    // MARK: - Pure loss (vacuum environment)

    /// Pure loss channel with transmissivity `eta`.
    ///
    /// Physics:
    ///   d' = K d
    ///   V' = K V Kᵀ + (1 - eta) I / 2
    public static func applyLoss(
        _ state: GaussianState,
        mode: Int,
        eta: Double
    ) throws -> GaussianState {

        guard (0.0...1.0).contains(eta) else {
            throw SimulatorError.invalidLowering("eta must be in [0,1]")
        }
        guard mode >= 0 && mode < state.modes else {
            throw SimulatorError.invalidLowering("invalid mode \(mode)")
        }

        let n = 2 * state.modes
        let i = 2 * mode
        let s = sqrt(eta)

        // K matrix
        var K = LA.eye(n)
        K[i][i] = s
        K[i + 1][i + 1] = s
        let KT = LA.transpose(K)

        // K V Kᵀ
        let KV = LA.matmul(K, state.cov)
        let Vscaled = LA.matmul(KV, KT)

        // Vacuum noise (1 - eta) / 2
        var N = LA.zeros(n, n)
        let noise = (1.0 - eta) * 0.5
        N[i][i] = noise
        N[i + 1][i + 1] = noise

        let Vout = LA.add(Vscaled, N)

        // Mean
        let dout = LA.matvec(K, state.mean)

        return GaussianState(
            modes: state.modes,
            mean: dout,
            cov: Vout
        )
    }

    // MARK: - Thermal loss

    /// Thermal loss channel with mean thermal photon number `nTh`.
    ///
    /// Physics:
    ///   d' = K d
    ///   V' = K V Kᵀ + (1 - eta)(2 nTh + 1) I / 2
    public static func applyThermalLoss(
        _ state: GaussianState,
        mode: Int,
        eta: Double,
        nTh: Double
    ) throws -> GaussianState {

        guard (0.0...1.0).contains(eta) else {
            throw SimulatorError.invalidLowering("eta must be in [0,1]")
        }
        guard nTh >= 0 else {
            throw SimulatorError.invalidLowering("nTh must be ≥ 0")
        }
        guard mode >= 0 && mode < state.modes else {
            throw SimulatorError.invalidLowering("invalid mode \(mode)")
        }

        let n = 2 * state.modes
        let i = 2 * mode
        let s = sqrt(eta)

        // K matrix
        var K = LA.eye(n)
        K[i][i] = s
        K[i + 1][i + 1] = s
        let KT = LA.transpose(K)

        // K V Kᵀ
        let KV = LA.matmul(K, state.cov)
        let Vscaled = LA.matmul(KV, KT)

        // Thermal noise
        let noise = (1.0 - eta) * (2.0 * nTh + 1.0) * 0.5
        var N = LA.zeros(n, n)
        N[i][i] = noise
        N[i + 1][i + 1] = noise

        let Vout = LA.add(Vscaled, N)

        // Mean
        let dout = LA.matvec(K, state.mean)

        return GaussianState(
            modes: state.modes,
            mean: dout,
            cov: Vout
        )
    }
}