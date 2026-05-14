import Foundation

public enum ClassicalComparator: String, Sendable, Equatable {
    case lt
    case le
    case gt
    case ge
    case eq
    case ne

    public static func parse(_ raw: String) -> ClassicalComparator? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lt", "<":
            return .lt
        case "le", "<=":
            return .le
        case "gt", ">":
            return .gt
        case "ge", ">=":
            return .ge
        case "eq", "==":
            return .eq
        case "ne", "!=":
            return .ne
        default:
            return nil
        }
    }

    public func evaluate(value: Double, threshold: Double) -> Bool {
        let eps = 1e-12
        switch self {
        case .lt:
            return value < threshold
        case .le:
            return value <= threshold
        case .gt:
            return value > threshold
        case .ge:
            return value >= threshold
        case .eq:
            return abs(value - threshold) <= eps
        case .ne:
            return abs(value - threshold) > eps
        }
    }
}

public struct ClassicalCondition: Sendable, Equatable {
    public let valueIndex: Int
    public let comparator: ClassicalComparator
    public let threshold: Double

    public init(valueIndex: Int, comparator: ClassicalComparator, threshold: Double) {
        self.valueIndex = valueIndex
        self.comparator = comparator
        self.threshold = threshold
    }
}

/// IR-level gate (logical description).
/// Backend-agnostic and validated by Circuit.
public indirect enum Gate: Sendable, Equatable {

    // Gaussian unitary gates
    case phase(theta: Double, mode: Int)
    case squeeze(r: Double, mode: Int)
    case beamSplitter(theta: Double, modeA: Int, modeB: Int)

    /// Phase-space displacement (q, p)
    case displace(q: Double, p: Double, mode: Int)

    // Channels / noise
    case loss(eta: Double, mode: Int)
    case thermalLoss(eta: Double, nTh: Double, mode: Int)

    /// Placeholder for future channels
    case noisePlaceholder(label: String)

    /// Non-Gaussian state injection (validated by backend)
    case injectNonGaussian(NonGaussianState)

    /// Classical feed-forward (recursive)
    case classicalControl(
        on: MeasurementID,
        condition: ClassicalCondition?,
        apply: Gate
    )

    /// Measurement-driven displacement:
    /// q' = gainQ * measurement[on][valueIndex] + biasQ
    /// p' = gainP * measurement[on][valueIndex] + biasP
    case feedbackDisplace(
        on: MeasurementID,
        valueIndex: Int,
        gainQ: Double,
        gainP: Double,
        biasQ: Double,
        biasP: Double,
        mode: Int
    )

    /// GKP nearest-lattice rounding decoder + correction displacement:
    /// 1) decode nearest lattice index from measurement[on][valueIndex]
    /// 2) correction = -nearestLatticeValue
    /// 3) q' = gainQ * correction + biasQ, p' = gainP * correction + biasP
    case gkpDecodeDisplace(
        on: MeasurementID,
        valueIndex: Int,
        latticeSpacing: Double,
        targetLatticeIndex: Int,
        gainQ: Double,
        gainP: Double,
        biasQ: Double,
        biasP: Double,
        mode: Int
    )

    // Measurements
    case measureHomodyne(mode: Int, theta: Double)
    case measureHeterodyne(mode: Int)
}
