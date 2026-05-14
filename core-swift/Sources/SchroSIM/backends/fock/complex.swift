import Foundation

public struct Complex: Sendable, Equatable {
    public var re: Double
    public var im: Double

    public init(_ re: Double = 0.0, _ im: Double = 0.0) {
        self.re = re
        self.im = im
    }

    public static let zero = Complex(0, 0)
    public static let one  = Complex(1, 0)
    public static let i    = Complex(0, 1)

    @inlinable public var conj: Complex { Complex(re, -im) }
    @inlinable public var abs2: Double { re*re + im*im }
    @inlinable public var abs: Double { sqrt(abs2) }
}

@inlinable public func + (lhs: Complex, rhs: Complex) -> Complex {
    Complex(lhs.re + rhs.re, lhs.im + rhs.im)
}
@inlinable public func - (lhs: Complex, rhs: Complex) -> Complex {
    Complex(lhs.re - rhs.re, lhs.im - rhs.im)
}
@inlinable public func * (lhs: Complex, rhs: Complex) -> Complex {
    Complex(lhs.re*rhs.re - lhs.im*rhs.im, lhs.re*rhs.im + lhs.im*rhs.re)
}
@inlinable public func * (lhs: Complex, rhs: Double) -> Complex {
    Complex(lhs.re*rhs, lhs.im*rhs)
}
@inlinable public func * (lhs: Double, rhs: Complex) -> Complex {
    Complex(lhs*rhs.re, lhs*rhs.im)
}
@inlinable public func / (lhs: Complex, rhs: Double) -> Complex {
    Complex(lhs.re/rhs, lhs.im/rhs)
}

public enum CxLA {
    public typealias CVec = [Complex]
    public typealias CMat = [[Complex]]

    public static func zeros(_ r: Int, _ c: Int) -> CMat {
        Array(repeating: Array(repeating: .zero, count: c), count: r)
    }

    public static func eye(_ n: Int) -> CMat {
        var m = zeros(n, n)
        for i in 0..<n { m[i][i] = .one }
        return m
    }

    public static func add(_ a: CMat, _ b: CMat) -> CMat {
        var out = a
        for i in 0..<a.count {
            for j in 0..<a[0].count { out[i][j] = out[i][j] + b[i][j] }
        }
        return out
    }

    public static func scale(_ a: CMat, _ alpha: Complex) -> CMat {
        var out = a
        for i in 0..<a.count {
            for j in 0..<a[0].count { out[i][j] = out[i][j] * alpha }
        }
        return out
    }

    public static func matmul(_ a: CMat, _ b: CMat) -> CMat {
        let r = a.count
        let k = a[0].count
        precondition(b.count == k)
        let c = b[0].count
        var out = zeros(r, c)
        for i in 0..<r {
            for j in 0..<c {
                var s = Complex.zero
                for kk in 0..<k {
                    s = s + a[i][kk] * b[kk][j]
                }
                out[i][j] = s
            }
        }
        return out
    }

    public static func matvec(_ a: CMat, _ x: CVec) -> CVec {
        let r = a.count
        let c = a[0].count
        precondition(x.count == c)
        var out = Array(repeating: Complex.zero, count: r)
        for i in 0..<r {
            var s = Complex.zero
            for j in 0..<c { s = s + a[i][j] * x[j] }
            out[i] = s
        }
        return out
    }

    /// Naive matrix exponential via truncated Taylor series.
    /// Works well for small cutoffs (e.g., 10–40) in MVP.
    public static func expm(_ A: CMat, terms: Int = 50) -> CMat {
        let n = A.count
        precondition(n > 0 && A[0].count == n)
        var result = eye(n)
        var term = eye(n) // A^0 / 0!
        for k in 1...terms {
            term = matmul(term, A) // A^k / (k-1)!
            let inv = 1.0 / Double(k)
            term = scale(term, Complex(inv, 0)) // A^k / k!
            result = add(result, term)
        }
        return result
    }
}

public enum MathUtil {
    @inlinable public static func factorial(_ n: Int) -> Double {
        if n < 2 { return 1.0 }
        return (2...n).reduce(1.0) { $0 * Double($1) }
    }

    @inlinable public static func sqrtFactorial(_ n: Int) -> Double {
        sqrt(factorial(n))
    }
}