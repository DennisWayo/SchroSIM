import Foundation

public struct FockState: Sendable {
    public let cutoff: Int
    /// Single-mode state vector |ψ> in number basis: ψ[n]
    public var psi: [Complex]

    public init(cutoff: Int, psi: [Complex]) {
        precondition(cutoff > 0)
        precondition(psi.count == cutoff)
        self.cutoff = cutoff
        self.psi = psi
    }

    public static func vacuum(cutoff: Int) -> FockState {
        var v = Array(repeating: Complex.zero, count: cutoff)
        v[0] = .one
        return FockState(cutoff: cutoff, psi: v)
    }

    public mutating func normalize() {
        let norm2 = psi.reduce(0.0) { $0 + $1.abs2 }
        let nrm = sqrt(max(norm2, 1e-300))
        psi = psi.map { $0 / nrm }
    }

    public func expectedPhotonNumber() -> Double {
        var s = 0.0
        for n in 0..<cutoff {
            s += Double(n) * psi[n].abs2
        }
        return s
    }
}

public enum FockStates {
    /// |α> truncated in Fock basis
    public static func coherent(alpha: Complex, cutoff: Int) -> FockState {
        let a2 = alpha.abs2
        let pref = exp(-0.5 * a2)
        var psi = Array(repeating: Complex.zero, count: cutoff)
        for n in 0..<cutoff {
            // α^n / sqrt(n!)
            var pow = Complex.one
            if n > 0 {
                for _ in 0..<n { pow = pow * alpha }
            }
            let coeff = pref / MathUtil.sqrtFactorial(n)
            psi[n] = pow * coeff
        }
        var st = FockState(cutoff: cutoff, psi: psi)
        st.normalize()
        return st
    }

    /// Even/odd cat: |α> ± |-α>
    public static func cat(alpha: Double, cutoff: Int, even: Bool = true) -> FockState {
        let a = Complex(alpha, 0)
        let ketP = coherent(alpha: a, cutoff: cutoff)
        let ketM = coherent(alpha: Complex(-alpha, 0), cutoff: cutoff)
        var psi = Array(repeating: Complex.zero, count: cutoff)
        for n in 0..<cutoff {
            psi[n] = even ? (ketP.psi[n] + ketM.psi[n]) : (ketP.psi[n] - ketM.psi[n])
        }
        var st = FockState(cutoff: cutoff, psi: psi)
        st.normalize()
        return st
    }

    public static func fock(n: Int, cutoff: Int) -> FockState {
        precondition(n >= 0 && n < cutoff)
        var psi = Array(repeating: Complex.zero, count: cutoff)
        psi[n] = .one
        return FockState(cutoff: cutoff, psi: psi)
    }
}