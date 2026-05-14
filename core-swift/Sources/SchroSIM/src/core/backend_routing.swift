import Foundation

public enum BackendRoutingError: Error, CustomStringConvertible {
    case incompatibleFockPath([String])

    public var description: String {
        switch self {
        case .incompatibleFockPath(let reasons):
            let joined = reasons.joined(separator: " ")
            return "Fock execution path is incompatible. \(joined)"
        }
    }
}

public enum BackendRouting {
    public static func requiresFockPath(_ circuit: Circuit) -> Bool {
        for gate in circuit.gates {
            guard case .injectNonGaussian(let ng) = gate else { continue }
            switch ng {
            case .fock, .cat:
                return true
            case .gkp:
                continue
            }
        }
        return false
    }

    public static func fockPathIssues(for circuit: Circuit) -> [String] {
        var issues: [String] = []

        if circuit.modes != 1 {
            issues.append("Fock path supports only single-mode circuits (got \(circuit.modes) modes).")
        }

        var unsupportedTypes: [String] = []
        unsupportedTypes.reserveCapacity(circuit.gates.count)
        for gate in circuit.gates {
            if isGateSupportedByFockPath(gate) {
                continue
            }
            unsupportedTypes.append(gateTypeName(gate))
        }

        if !unsupportedTypes.isEmpty {
            let unique = Array(Set(unsupportedTypes)).sorted()
            issues.append(
                "Unsupported gates for Fock path: \(unique.joined(separator: ", ")). " +
                    "Supported: phase, displace, inject_fock, inject_cat."
            )
        }

        return issues
    }

    public static func assertFockCompatible(_ circuit: Circuit) throws {
        let issues = fockPathIssues(for: circuit)
        if !issues.isEmpty {
            throw BackendRoutingError.incompatibleFockPath(issues)
        }
    }

    public static func resolveExecutionBackend(
        requestedBackend: String,
        circuit: Circuit
    ) throws -> String {
        switch requestedBackend {
        case "gaussian":
            return "gaussian"
        case "fock":
            try assertFockCompatible(circuit)
            return "fock"
        case "auto", "hybrid":
            if requiresFockPath(circuit) {
                try assertFockCompatible(circuit)
                return "fock"
            }
            return "gaussian"
        default:
            return requestedBackend
        }
    }

    private static func isGateSupportedByFockPath(_ gate: Gate) -> Bool {
        switch gate {
        case .phase, .displace:
            return true
        case .injectNonGaussian(let ng):
            switch ng {
            case .fock, .cat:
                return true
            case .gkp:
                return false
            }
        default:
            return false
        }
    }

    private static func gateTypeName(_ gate: Gate) -> String {
        switch gate {
        case .phase:
            return "phase"
        case .squeeze:
            return "squeeze"
        case .beamSplitter:
            return "beam_splitter"
        case .displace:
            return "displace"
        case .loss:
            return "loss"
        case .thermalLoss:
            return "thermal_loss"
        case .noisePlaceholder:
            return "noise_placeholder"
        case .injectNonGaussian(let ng):
            switch ng {
            case .fock:
                return "inject_fock"
            case .cat:
                return "inject_cat"
            case .gkp:
                return "inject_gkp"
            }
        case .classicalControl:
            return "classical_control"
        case .feedbackDisplace:
            return "feedback_displace"
        case .gkpDecodeDisplace:
            return "gkp_decode_displace"
        case .measureHomodyne:
            return "measure_homodyne"
        case .measureHeterodyne:
            return "measure_heterodyne"
        }
    }
}
