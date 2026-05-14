import Foundation

public enum MeasurementKind: Sendable, Equatable {
    case homodyne(theta: Double)
    case heterodyne
}

public struct MeasurementEvent: Sendable, Equatable {
    public let index: Int          // gate index in circuit
    public let mode: Int
    public let kind: MeasurementKind
    public let values: [Double]    // homodyne: [x], heterodyne: [q, p]
}

public enum MeasurementError: Error, CustomStringConvertible {
    case singularCovariance(String)

    public var description: String {
        switch self {
        case .singularCovariance(let msg): return "Measurement failed (singular): \(msg)"
        }
    }
}

/// Gaussian measurement and conditioning utilities.
/// Implements linear-Gaussian conditioning on quadratures.
public enum GaussianMeasurement {

    // MARK: - Public API (deterministic conditioning)

    /// Condition on an explicit homodyne outcome y for x_theta = q cosθ + p sinθ.
    /// Optional vMeas adds classical measurement noise variance (ideal homodyne: 0).
    public static func conditionHomodyne(
        state: GaussianState,
        mode: Int,
        theta: Double,
        outcome y: Double,
        vMeas: Double = 0.0
    ) throws -> GaussianState {
        let dim = 2 * state.modes
        let h = homodyneVector(dim: dim, mode: mode, theta: theta)

        let mu = LA.dot(h, state.mean)                     // h^T m
        let Vh = LA.matvec(state.cov, h)                  // V h
        let s2 = LA.dot(h, Vh) + vMeas                    // h^T V h + v

        if s2 <= 0.0 {
            throw MeasurementError.singularCovariance("Non-positive measurement variance s2=\(s2)")
        }

        // m' = m + Vh * (y - mu) / s2
        let gain = (y - mu) / s2
        let delta = LA.scale(Vh, gain)
        let newMean = LA.add(state.mean, delta)

        // V' = V - (Vh Vh^T) / s2
        let correction = LA.scale(LA.outer(Vh, Vh), 1.0 / s2)
        let newCov = LA.sub(state.cov, correction)

        var out = state
        out.mean = newMean
        out.cov = newCov
        return out
    }

    /// Condition on an explicit heterodyne outcome (q,p) for one mode.
    /// Modeled as measuring both q and p with added vacuum noise R = (1/2) I_2.
    public static func conditionHeterodyne(
        state: GaussianState,
        mode: Int,
        outcome qp: (Double, Double)
    ) throws -> GaussianState {
        let dim = 2 * state.modes
        let (H, R) = heterodyneMatrices(dim: dim, mode: mode)

        // S = H V H^T + R   (2x2)
        let HV = LA.matmul(H, state.cov)                   // 2 x dim
        let HVT = LA.matmul(HV, LA.transpose(H))           // 2 x 2
        let S = LA.add(HVT, R)

        guard let Sinv = LA.inv2x2(S) else {
            throw MeasurementError.singularCovariance("Could not invert heterodyne innovation matrix.")
        }

        // residual = y - H m   (2)
        let y = [qp.0, qp.1]
        let Hm = LA.matvec(H, state.mean)
        let residual = [y[0] - Hm[0], y[1] - Hm[1]]

        // K = V H^T S^{-1}  (dim x 2)
        let VHT = LA.matmul(state.cov, LA.transpose(H))    // dim x 2
        let K = LA.matmul(VHT, Sinv)                       // dim x 2

        // m' = m + K residual
        let Kres = LA.matvec(K, residual)
        let newMean = LA.add(state.mean, Kres)

        // V' = V - K (H V)
        // (H V) is HV (2 x dim), so K*HV is (dim x dim)
        let KHV = LA.matmul(K, HV)
        let newCov = LA.sub(state.cov, KHV)

        var out = state
        out.mean = newMean
        out.cov = newCov
        return out
    }

    // MARK: - Sampling helpers (random outcomes)

    public static func sampleHomodyne(
        from state: GaussianState,
        mode: Int,
        theta: Double,
        rng: inout any RandomNumberGenerator,
        vMeas: Double = 0.0
    ) throws -> (outcome: Double, post: GaussianState) {
        let dim = 2 * state.modes
        let h = homodyneVector(dim: dim, mode: mode, theta: theta)

        let mu = LA.dot(h, state.mean)
        let Vh = LA.matvec(state.cov, h)
        let s2 = LA.dot(h, Vh) + vMeas
        if s2 <= 0.0 {
            throw MeasurementError.singularCovariance("Non-positive measurement variance s2=\(s2)")
        }

        let z = standardNormal(&rng)
        let y = mu + sqrt(s2) * z
        let post = try conditionHomodyne(state: state, mode: mode, theta: theta, outcome: y, vMeas: vMeas)
        return (y, post)
    }

    public static func sampleHeterodyne(
        from state: GaussianState,
        mode: Int,
        rng: inout any RandomNumberGenerator
    ) throws -> (outcome: (Double, Double), post: GaussianState) {
        // y ~ N(Hm, S) where S = H V H^T + R
        let dim = 2 * state.modes
        let (H, R) = heterodyneMatrices(dim: dim, mode: mode)
        let mu = LA.matvec(H, state.mean) // 2

        let HV = LA.matmul(H, state.cov)
        let HVT = LA.matmul(HV, LA.transpose(H))
        let S = LA.add(HVT, R)            // 2x2

        // Sample from 2D Gaussian with mean mu and cov S:
        // Use Cholesky for 2x2 explicitly.
        let (l00, l10, l11) = try cholesky2x2(S)
        let z0 = standardNormal(&rng)
        let z1 = standardNormal(&rng)

        let e0 = l00 * z0
        let e1 = l10 * z0 + l11 * z1

        let y0 = mu[0] + e0
        let y1 = mu[1] + e1

        let post = try conditionHeterodyne(state: state, mode: mode, outcome: (y0, y1))
        return ((y0, y1), post)
    }

    // MARK: - Internals

    private static func homodyneVector(dim: Int, mode: Int, theta: Double) -> Vec {
        var h = Array(repeating: 0.0, count: dim)
        let i = 2 * mode
        h[i] = cos(theta)     // q coefficient
        h[i + 1] = sin(theta) // p coefficient
        return h
    }

    private static func heterodyneMatrices(dim: Int, mode: Int) -> (H: Mat, R: Mat) {
        // H selects q and p of a single mode: y = [q, p]
        var H = LA.zeros(2, dim)
        let i = 2 * mode
        H[0][i] = 1.0
        H[1][i + 1] = 1.0

        // Added vacuum noise for heterodyne: R = (1/2) I2
        let R: Mat = [
            [0.5, 0.0],
            [0.0, 0.5]
        ]
        return (H, R)
    }

    /// Standard normal via Box–Muller
    private static func standardNormal(_ rng: inout any RandomNumberGenerator) -> Double {
        // Avoid log(0)
        var u1 = Double.random(in: 0..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        if u1 < 1e-16 { u1 = 1e-16 }
        return sqrt(-2.0 * log(u1)) * cos(2.0 * Double.pi * u2)
    }

    /// Cholesky for 2x2 SPD matrix:
    /// [a b; b c] = [l00 0; l10 l11] [l00 l10; 0 l11]
    private static func cholesky2x2(_ S: Mat, tol: Double = 1e-14) throws -> (Double, Double, Double) {
        let a = S[0][0]
        let b = S[0][1]
        let c = S[1][1]
        if a <= tol { throw MeasurementError.singularCovariance("Cholesky failed: a<=0") }
        let l00 = sqrt(a)
        let l10 = b / l00
        let t = c - l10 * l10
        if t <= tol { throw MeasurementError.singularCovariance("Cholesky failed: t<=0") }
        let l11 = sqrt(t)
        return (l00, l10, l11)
    }
}