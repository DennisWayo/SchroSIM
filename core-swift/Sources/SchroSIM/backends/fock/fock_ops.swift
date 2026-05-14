import Foundation

public enum FockOps {

    /// Annihilation operator a (single mode) in cutoff dimension
    public static func annihilation(cutoff: Int) -> CxLA.CMat {
        var a = CxLA.zeros(cutoff, cutoff)
        for n in 1..<cutoff {
            // <n-1| a |n> = sqrt(n)
            a[n-1][n] = Complex(sqrt(Double(n)), 0)
        }
        return a
    }

    public static func creation(cutoff: Int) -> CxLA.CMat {
        var ad = CxLA.zeros(cutoff, cutoff)
        for n in 0..<(cutoff-1) {
            // <n+1| a† |n> = sqrt(n+1)
            ad[n+1][n] = Complex(sqrt(Double(n+1)), 0)
        }
        return ad
    }

    /// Phase rotation R(θ) = exp(-i θ a†a)
    public static func phase(theta: Double, cutoff: Int) -> CxLA.CMat {
        var U = CxLA.zeros(cutoff, cutoff)
        for n in 0..<cutoff {
            let ang = -theta * Double(n)
            U[n][n] = Complex(cos(ang), sin(ang))
        }
        return U
    }

    /// Displacement D(α) = exp(α a† - α* a)
    /// Implemented via expm of truncated generator.
    public static func displace(alpha: Complex, cutoff: Int, terms: Int = 60) -> CxLA.CMat {
        let a = annihilation(cutoff: cutoff)
        let ad = creation(cutoff: cutoff)

        // G = α a† - α* a
        let G1 = CxLA.scale(ad, alpha)
        let G2 = CxLA.scale(a, Complex(-alpha.conj.re, -alpha.conj.im)) // -(α*) a
        let G = CxLA.add(G1, G2)

        return CxLA.expm(G, terms: terms)
    }

    public static func apply(_ U: CxLA.CMat, to st: FockState) -> FockState {
        let out = CxLA.matvec(U, st.psi)
        var s = FockState(cutoff: st.cutoff, psi: out)
        s.normalize()
        return s
    }
}