import Foundation

#if canImport(Metal)
import Metal
#endif

public enum ComputeBackend: String, CaseIterable, Sendable {
    case auto
    case cpu
    case metal
}

public struct ComputeWorkloadProfile: Sendable {
    public let modes: Int
    public let gateCount: Int
    public let includesFockPath: Bool
    public let includesMeasurements: Bool

    public var matrixDimension: Int { 2 * modes }

    public init(
        modes: Int,
        gateCount: Int,
        includesFockPath: Bool,
        includesMeasurements: Bool
    ) {
        self.modes = modes
        self.gateCount = gateCount
        self.includesFockPath = includesFockPath
        self.includesMeasurements = includesMeasurements
    }
}

public struct ComputeBackendResolution: Sendable {
    public let requested: ComputeBackend
    public let candidate: ComputeBackend
    public let used: ComputeBackend
    public let fallbackReason: String?

    public init(
        requested: ComputeBackend,
        candidate: ComputeBackend,
        used: ComputeBackend,
        fallbackReason: String?
    ) {
        self.requested = requested
        self.candidate = candidate
        self.used = used
        self.fallbackReason = fallbackReason
    }
}

public enum ComputeBackendResolver {
    private enum AutoMetalHeuristics {
        // Tuned from mode/depth sweep data:
        // 2x{24,64} should stay CPU-candidate, while 8x8 and above can route to Metal.
        static let minModesForMetal = 8
        static let minGateCountForMetal = 192
        static let minMatrixDimensionForMetal = 24
        static let minWorkScoreForMetal = 12_000
        static let minGateCountAnyModes = 2_048
    }

    public static var metalAvailable: Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    public static var metalExecutionAvailable: Bool {
        #if canImport(Metal) && canImport(MetalPerformanceShaders)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    public static func resolve(
        requested: ComputeBackend,
        workload: ComputeWorkloadProfile
    ) -> ComputeBackendResolution {
        let candidate: ComputeBackend
        switch requested {
        case .auto:
            candidate = shouldPreferMetal(workload: workload) ? .metal : .cpu
        case .cpu:
            candidate = .cpu
        case .metal:
            candidate = .metal
        }

        if candidate == .cpu {
            return ComputeBackendResolution(
                requested: requested,
                candidate: candidate,
                used: .cpu,
                fallbackReason: nil
            )
        }

        guard metalAvailable else {
            return ComputeBackendResolution(
                requested: requested,
                candidate: candidate,
                used: .cpu,
                fallbackReason: "metal_device_unavailable"
            )
        }
        guard metalExecutionAvailable else {
            return ComputeBackendResolution(
                requested: requested,
                candidate: candidate,
                used: .cpu,
                fallbackReason: "metal_runtime_unavailable"
            )
        }
        return ComputeBackendResolution(
            requested: requested,
            candidate: candidate,
            used: .metal,
            fallbackReason: nil
        )
    }

    private static func shouldPreferMetal(workload: ComputeWorkloadProfile) -> Bool {
        guard metalExecutionAvailable else { return false }
        if workload.includesFockPath { return true }

        let gateCount = workload.gateCount
        let matrixDimension = workload.matrixDimension
        let workScore = workload.modes * workload.modes * gateCount

        if gateCount >= AutoMetalHeuristics.minGateCountAnyModes { return true }
        if matrixDimension >= AutoMetalHeuristics.minMatrixDimensionForMetal, gateCount >= 128 {
            return true
        }
        if workload.modes >= AutoMetalHeuristics.minModesForMetal,
           gateCount >= AutoMetalHeuristics.minGateCountForMetal {
            return true
        }
        if workScore >= AutoMetalHeuristics.minWorkScoreForMetal { return true }
        return false
    }
}
