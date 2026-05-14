import Foundation

public enum FoundryValidationError: Error, CustomStringConvertible {
    case invalidMaxModes(Int)
    case modeCountExceedsLimit(actual: Int, max: Int)
    case invalidSqueezingLimit(Double)
    case squeezingLimitExceeded(mode: Int, value: Double, max: Double)
    case modeLossLengthMismatch(expected: Int, actual: Int)
    case invalidModeLoss(mode: Int, value: Double)
    case nonGaussianDisallowed(NonGaussianState)
    case measurementsDisallowed
    case unsupportedPlaceholderGate(String)

    public var description: String {
        switch self {
        case .invalidMaxModes(let value):
            return "Foundry maxModes must be > 0, got \(value)"
        case .modeCountExceedsLimit(let actual, let max):
            return "Circuit modes \(actual) exceed foundry limit \(max)"
        case .invalidSqueezingLimit(let value):
            return "Foundry maxSqueezingR must be finite and >= 0, got \(value)"
        case .squeezingLimitExceeded(let mode, let value, let max):
            return "Squeezing on mode \(mode) exceeds foundry maxSqueezingR \(max): got \(value)"
        case .modeLossLengthMismatch(let expected, let actual):
            return "Foundry modeLossEta must have \(expected) values, got \(actual)"
        case .invalidModeLoss(let mode, let value):
            return "Foundry modeLossEta[\(mode)] must be finite in [0,1], got \(value)"
        case .nonGaussianDisallowed(let state):
            return "Foundry disallows non-Gaussian injection: \(state)"
        case .measurementsDisallowed:
            return "Foundry disallows measurement gates"
        case .unsupportedPlaceholderGate(let label):
            return "Foundry rejects placeholder gate '\(label)'"
        }
    }
}

public struct FoundrySpec: Sendable, Equatable {
    public let name: String
    public let maxModes: Int?
    public let maxSqueezingR: Double?
    public let allowNonGaussian: Bool
    public let allowMeasurements: Bool
    public let modeLossEta: [Double]
    public let injectModeLoss: Bool

    public init(
        name: String,
        maxModes: Int? = nil,
        maxSqueezingR: Double? = nil,
        allowNonGaussian: Bool = true,
        allowMeasurements: Bool = true,
        modeLossEta: [Double] = [],
        injectModeLoss: Bool = true
    ) {
        self.name = name
        self.maxModes = maxModes
        self.maxSqueezingR = maxSqueezingR
        self.allowNonGaussian = allowNonGaussian
        self.allowMeasurements = allowMeasurements
        self.modeLossEta = modeLossEta
        self.injectModeLoss = injectModeLoss
    }
}

public enum FoundryCompiler {
    public static func compile(_ circuit: Circuit, with spec: FoundrySpec) throws -> Circuit {
        try validate(circuit, with: spec)
        let lowered = try clone(circuit)

        guard spec.injectModeLoss else {
            return lowered
        }

        for mode in 0..<spec.modeLossEta.count {
            let eta = spec.modeLossEta[mode]
            if eta < 1.0 {
                try lowered.append(.loss(eta: eta, mode: mode))
            }
        }

        return lowered
    }

    public static func validate(_ circuit: Circuit, with spec: FoundrySpec) throws {
        if let maxModes = spec.maxModes {
            guard maxModes > 0 else {
                throw FoundryValidationError.invalidMaxModes(maxModes)
            }
            if circuit.modes > maxModes {
                throw FoundryValidationError.modeCountExceedsLimit(actual: circuit.modes, max: maxModes)
            }
        }

        if let maxR = spec.maxSqueezingR {
            guard maxR.isFinite, maxR >= 0.0 else {
                throw FoundryValidationError.invalidSqueezingLimit(maxR)
            }
        }

        if !spec.modeLossEta.isEmpty {
            if spec.modeLossEta.count != circuit.modes {
                throw FoundryValidationError.modeLossLengthMismatch(
                    expected: circuit.modes,
                    actual: spec.modeLossEta.count
                )
            }
            for mode in 0..<spec.modeLossEta.count {
                let eta = spec.modeLossEta[mode]
                if !eta.isFinite || eta < 0.0 || eta > 1.0 {
                    throw FoundryValidationError.invalidModeLoss(mode: mode, value: eta)
                }
            }
        }

        for gate in circuit.gates {
            switch gate {
            case .squeeze(let r, let mode):
                if let maxR = spec.maxSqueezingR, abs(r) > maxR {
                    throw FoundryValidationError.squeezingLimitExceeded(mode: mode, value: r, max: maxR)
                }
            case .injectNonGaussian(let ng):
                if !spec.allowNonGaussian {
                    throw FoundryValidationError.nonGaussianDisallowed(ng)
                }
            case .measureHomodyne, .measureHeterodyne, .feedbackDisplace, .gkpDecodeDisplace:
                if !spec.allowMeasurements {
                    throw FoundryValidationError.measurementsDisallowed
                }
            case .noisePlaceholder(let label):
                throw FoundryValidationError.unsupportedPlaceholderGate(label)
            default:
                continue
            }
        }
    }

    private static func clone(_ circuit: Circuit) throws -> Circuit {
        try Circuit(modes: circuit.modes, gates: circuit.gates)
    }
}
