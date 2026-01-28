import Foundation

public typealias Vec = [Double]
public typealias Mat = [[Double]]

public enum LA {
    public static func zeros(_ r: Int, _ c: Int) -> Mat {
        Array(repeating: Array(repeating: 0.0, count: c), count: r)
    }

    public static func dot(_ a: Vec, _ b: Vec) -> Double {
        precondition(a.count == b.count)
        var s = 0.0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    public static func scale(_ a: Mat, _ alpha: Double) -> Mat {
        var out = a
        for i in 0..<a.count {
            for j in 0..<a[0].count { out[i][j] *= alpha }
        }
        return out
    }

    public static func scale(_ v: Vec, _ alpha: Double) -> Vec {
        v.map { $0 * alpha }
    }

    public static func sub(_ a: Mat, _ b: Mat) -> Mat {
        precondition(a.count == b.count && a.first?.count == b.first?.count)
        var out = a
        for i in 0..<a.count {
            for j in 0..<a[0].count { out[i][j] -= b[i][j] }
        }
        return out
    }

    public static func outer(_ a: Vec, _ b: Vec) -> Mat {
        var out = zeros(a.count, b.count)
        for i in 0..<a.count {
            for j in 0..<b.count { out[i][j] = a[i] * b[j] }
        }
        return out
    }

    /// Inverse of a 2x2 matrix.
    /// Returns nil if singular (within tolerance).
    public static func inv2x2(_ m: Mat, tol: Double = 1e-14) -> Mat? {
        guard m.count == 2, m[0].count == 2, m[1].count == 2 else { return nil }
        let a = m[0][0], b = m[0][1]
        let c = m[1][0], d = m[1][1]
        let det = a*d - b*c
        if abs(det) < tol { return nil }
        let invDet = 1.0 / det
        return [
            [ d * invDet, -b * invDet],
            [-c * invDet,  a * invDet]
        ]
    }

    public static func eye(_ n: Int) -> Mat {
        var m = zeros(n, n)
        for i in 0..<n { m[i][i] = 1.0 }
        return m
    }

    public static func transpose(_ a: Mat) -> Mat {
        precondition(!a.isEmpty)
        let r = a.count
        let c = a[0].count
        var t = zeros(c, r)
        for i in 0..<r {
            precondition(a[i].count == c)
            for j in 0..<c { t[j][i] = a[i][j] }
        }
        return t
    }

    public static func matmul(_ a: Mat, _ b: Mat) -> Mat {
        precondition(!a.isEmpty && !b.isEmpty)
        let r = a.count
        let k = a[0].count
        precondition(b.count == k)
        let c = b[0].count
        for row in a { precondition(row.count == k) }
        for row in b { precondition(row.count == c) }

        var out = zeros(r, c)
        for i in 0..<r {
            for j in 0..<c {
                var s = 0.0
                for kk in 0..<k {
                    s += a[i][kk] * b[kk][j]
                }
                out[i][j] = s
            }
        }
        return out
    }

    public static func matvec(_ a: Mat, _ x: Vec) -> Vec {
        precondition(!a.isEmpty)
        let r = a.count
        let c = a[0].count
        precondition(x.count == c)
        for row in a { precondition(row.count == c) }

        var out = Array(repeating: 0.0, count: r)
        for i in 0..<r {
            var s = 0.0
            for j in 0..<c { s += a[i][j] * x[j] }
            out[i] = s
        }
        return out
    }

    public static func add(_ a: Mat, _ b: Mat) -> Mat {
        precondition(a.count == b.count && a.first?.count == b.first?.count)
        var out = a
        for i in 0..<a.count {
            for j in 0..<a[0].count { out[i][j] += b[i][j] }
        }
        return out
    }

    public static func add(_ a: Vec, _ b: Vec) -> Vec {
        precondition(a.count == b.count)
        return zip(a, b).map(+)
    }

    public static func symplecticForm(modes: Int) -> Mat {
        // Ω = ⊕_m [[0,1],[-1,0]]
        let n = 2 * modes
        var omega = zeros(n, n)
        for m in 0..<modes {
            let i = 2*m
            omega[i][i+1] =  1.0
            omega[i+1][i] = -1.0
        }
        return omega
    }

    public static func approxEqual(_ a: Mat, _ b: Mat, tol: Double = 1e-9) -> Bool {
        guard a.count == b.count, a.first?.count == b.first?.count else { return false }
        for i in 0..<a.count {
            for j in 0..<a[0].count {
                if abs(a[i][j] - b[i][j]) > tol { return false }
            }
        }
        return true
    }
}

