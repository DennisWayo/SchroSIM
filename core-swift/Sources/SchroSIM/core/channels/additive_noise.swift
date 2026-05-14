import Foundation

public enum GaussianAdditiveNoise {
    /// Adds independent Gaussian noise on q/p for the target mode:
    /// Σ -> Σ + diag([vq, vp]) on that mode.
    public static func apply(_ state: GaussianState, mode: Int, vq: Double, vp: Double) throws -> GaussianState {
        precondition(mode >= 0 && mode < state.modes)
        var cov = state.cov
        let iq = 2 * mode
        let ip = iq + 1
        cov[iq][iq] += vq
        cov[ip][ip] += vp
        return GaussianState(modes: state.modes, mean: state.mean, cov: cov)
    }
}