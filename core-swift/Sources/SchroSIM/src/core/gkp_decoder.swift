import Foundation

public struct GKPNearestLatticeDecodeResult: Sendable, Equatable {
    public let latticeSpacing: Double
    public let targetLatticeIndex: Int
    public let nearestLatticeIndex: Int
    public let nearestLatticeValue: Double
    public let residual: Double
    public let correction: Double
    public let logicalPass: Bool
}

public enum GKPNearestLatticeDecoder {
    public static func decode(
        syndromeValue: Double,
        latticeSpacing: Double,
        targetLatticeIndex: Int
    ) -> GKPNearestLatticeDecodeResult {
        let nearestLatticeIndex = Int((syndromeValue / latticeSpacing).rounded())
        let nearestLatticeValue = Double(nearestLatticeIndex) * latticeSpacing
        let residual = syndromeValue - nearestLatticeValue
        let correction = -nearestLatticeValue
        let logicalPass = nearestLatticeIndex == targetLatticeIndex
        return GKPNearestLatticeDecodeResult(
            latticeSpacing: latticeSpacing,
            targetLatticeIndex: targetLatticeIndex,
            nearestLatticeIndex: nearestLatticeIndex,
            nearestLatticeValue: nearestLatticeValue,
            residual: residual,
            correction: correction,
            logicalPass: logicalPass
        )
    }
}
