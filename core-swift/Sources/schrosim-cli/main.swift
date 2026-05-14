import Darwin
import CryptoKit
import Foundation
import SchroSIM

enum CLICommand: String {
    case version
    case info
    case run
    case trace
    case traceStream = "trace-stream"
    case traceShare = "trace-share"
    case benchmark
    case foundryAdmin = "foundry-admin"
}

enum CLIInputError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case missingField(String)
    case invalidField(String)
    case unsupportedGate(String)
    case unsupportedNonGaussian(String)

    var description: String {
        switch self {
        case .invalidArguments(let message),
             .missingField(let message),
             .invalidField(let message),
             .unsupportedGate(let message),
             .unsupportedNonGaussian(let message):
            return message
        }
    }
}

struct CircuitInput: Decodable {
    let schemaVersion: Int?
    let modes: Int
    let backend: String?
    let seed: UInt64?
    let initialState: String?
    let cutoff: Int?
    let foundry: FoundryInput?
    let foundryProfile: FoundryProfileRefInput?
    let gates: [GateInput]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case modes
        case backend
        case seed
        case initialState = "initial_state"
        case cutoff
        case foundry
        case foundryProfile = "foundry_profile"
        case gates
    }
}

struct FoundryProfileRefInput: Decodable {
    let profileID: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case version
    }
}

struct FoundryInput: Decodable {
    let name: String?
    let maxModes: Int?
    let maxSqueezingR: Double?
    let allowNonGaussian: Bool?
    let allowMeasurements: Bool?
    let modeLossEta: [Double]?
    let injectModeLoss: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case maxModes = "max_modes"
        case maxSqueezingR = "max_squeezing_r"
        case allowNonGaussian = "allow_non_gaussian"
        case allowMeasurements = "allow_measurements"
        case modeLossEta = "mode_loss_eta"
        case injectModeLoss = "inject_mode_loss"
    }

    func toSpec(defaultName: String = "foundry") -> FoundrySpec {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let trimmed, !trimmed.isEmpty {
            resolvedName = trimmed
        } else {
            resolvedName = defaultName
        }

        return FoundrySpec(
            name: resolvedName,
            maxModes: maxModes,
            maxSqueezingR: maxSqueezingR,
            allowNonGaussian: allowNonGaussian ?? true,
            allowMeasurements: allowMeasurements ?? true,
            modeLossEta: modeLossEta ?? [],
            injectModeLoss: injectModeLoss ?? true
        )
    }
}

struct GateInput: Decodable {
    let type: String
    let mode: Int?
    let modeA: Int?
    let modeB: Int?
    let theta: Double?
    let r: Double?
    let q: Double?
    let p: Double?
    let eta: Double?
    let nTh: Double?
    let label: String?
    let state: String?
    let n: Int?
    let alpha: Double?
    let delta: Double?
    let on: Int?
    let onValueIndex: Int?
    let onComparator: String?
    let onThreshold: Double?
    let applyType: String?
    let applyMode: Int?
    let applyModeA: Int?
    let applyModeB: Int?
    let applyTheta: Double?
    let applyR: Double?
    let applyQ: Double?
    let applyP: Double?
    let applyEta: Double?
    let applyNTh: Double?
    let applyN: Int?
    let applyAlpha: Double?
    let applyDelta: Double?
    let sourceValueIndex: Int?
    let gainQ: Double?
    let gainP: Double?
    let biasQ: Double?
    let biasP: Double?
    let decoder: String?
    let latticeSpacing: Double?
    let targetLatticeIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case mode
        case modeA = "mode_a"
        case modeB = "mode_b"
        case theta
        case r
        case q
        case p
        case eta
        case nTh = "n_th"
        case label
        case state
        case n
        case alpha
        case delta
        case on
        case onValueIndex = "on_value_index"
        case onComparator = "on_comparator"
        case onThreshold = "on_threshold"
        case applyType = "apply_type"
        case applyMode = "apply_mode"
        case applyModeA = "apply_mode_a"
        case applyModeB = "apply_mode_b"
        case applyTheta = "apply_theta"
        case applyR = "apply_r"
        case applyQ = "apply_q"
        case applyP = "apply_p"
        case applyEta = "apply_eta"
        case applyNTh = "apply_n_th"
        case applyN = "apply_n"
        case applyAlpha = "apply_alpha"
        case applyDelta = "apply_delta"
        case sourceValueIndex = "source_value_index"
        case gainQ = "gain_q"
        case gainP = "gain_p"
        case biasQ = "bias_q"
        case biasP = "bias_p"
        case decoder
        case latticeSpacing = "lattice_spacing"
        case targetLatticeIndex = "target_lattice_index"
    }

    func toGate() throws -> Gate {
        let normalized = type.lowercased()
        switch normalized {
        case "phase":
            return .phase(
                theta: try require(theta, "theta"),
                mode: try require(mode, "mode")
            )
        case "squeeze":
            return .squeeze(
                r: try require(r, "r"),
                mode: try require(mode, "mode")
            )
        case "beam_splitter", "beamsplitter":
            return .beamSplitter(
                theta: try require(theta, "theta"),
                modeA: try require(modeA, "mode_a"),
                modeB: try require(modeB, "mode_b")
            )
        case "displace":
            return .displace(
                q: try require(q, "q"),
                p: try require(p, "p"),
                mode: try require(mode, "mode")
            )
        case "loss":
            return .loss(
                eta: try require(eta, "eta"),
                mode: try require(mode, "mode")
            )
        case "thermal_loss", "thermalloss":
            return .thermalLoss(
                eta: try require(eta, "eta"),
                nTh: try require(nTh, "n_th"),
                mode: try require(mode, "mode")
            )
        case "measure_homodyne", "homodyne":
            return .measureHomodyne(
                mode: try require(mode, "mode"),
                theta: try require(theta, "theta")
            )
        case "measure_heterodyne", "heterodyne":
            return .measureHeterodyne(
                mode: try require(mode, "mode")
            )
        case "noise_placeholder":
            return .noisePlaceholder(
                label: label ?? "placeholder"
            )
        case "inject_non_gaussian", "inject_nongaussian", "inject":
            return .injectNonGaussian(try parseNonGaussian(stateLabel: state))
        case "inject_fock":
            return .injectNonGaussian(.fock(
                n: try require(n, "n"),
                mode: try require(mode, "mode")
            ))
        case "inject_cat":
            return .injectNonGaussian(.cat(
                alpha: try require(alpha, "alpha"),
                mode: try require(mode, "mode")
            ))
        case "inject_gkp":
            return .injectNonGaussian(.gkp(
                delta: try require(delta, "delta"),
                mode: try require(mode, "mode")
            ))
        case "feedback_displace":
            let on = try require(on, "on")
            guard on >= 0 else {
                throw CLIInputError.invalidField("Gate '\(type)' field 'on' must be >= 0")
            }
            let valueIndex = sourceValueIndex ?? 0
            guard valueIndex >= 0 else {
                throw CLIInputError.invalidField("Gate '\(type)' field 'source_value_index' must be >= 0")
            }
            let gainQ = gainQ ?? 1.0
            let gainP = gainP ?? 0.0
            let biasQ = biasQ ?? 0.0
            let biasP = biasP ?? 0.0
            guard gainQ.isFinite, gainP.isFinite, biasQ.isFinite, biasP.isFinite else {
                throw CLIInputError.invalidField(
                    "Gate '\(type)' fields gain_q/gain_p/bias_q/bias_p must be finite"
                )
            }
            if let decoderLabel = decoder?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !decoderLabel.isEmpty {
                guard decoderLabel == "gkp_nearest_lattice" || decoderLabel == "gkp_rounding" else {
                    throw CLIInputError.invalidField(
                        "Unsupported decoder '\(decoderLabel)' for gate '\(type)'. Supported: gkp_nearest_lattice, gkp_rounding."
                    )
                }
                let spacing = latticeSpacing ?? sqrt(Double.pi)
                guard spacing.isFinite, spacing > 0 else {
                    throw CLIInputError.invalidField(
                        "Gate '\(type)' field 'lattice_spacing' must be > 0 and finite"
                    )
                }
                return .gkpDecodeDisplace(
                    on: on,
                    valueIndex: valueIndex,
                    latticeSpacing: spacing,
                    targetLatticeIndex: targetLatticeIndex ?? 0,
                    gainQ: gainQ,
                    gainP: gainP,
                    biasQ: biasQ,
                    biasP: biasP,
                    mode: try require(mode, "mode")
                )
            }
            return .feedbackDisplace(
                on: on,
                valueIndex: valueIndex,
                gainQ: gainQ,
                gainP: gainP,
                biasQ: biasQ,
                biasP: biasP,
                mode: try require(mode, "mode")
            )
        case "gkp_decode_displace":
            let on = try require(on, "on")
            guard on >= 0 else {
                throw CLIInputError.invalidField("Gate '\(type)' field 'on' must be >= 0")
            }
            let valueIndex = sourceValueIndex ?? 0
            guard valueIndex >= 0 else {
                throw CLIInputError.invalidField("Gate '\(type)' field 'source_value_index' must be >= 0")
            }
            let spacing = latticeSpacing ?? sqrt(Double.pi)
            guard spacing.isFinite, spacing > 0 else {
                throw CLIInputError.invalidField(
                    "Gate '\(type)' field 'lattice_spacing' must be > 0 and finite"
                )
            }
            let gainQ = gainQ ?? 1.0
            let gainP = gainP ?? 0.0
            let biasQ = biasQ ?? 0.0
            let biasP = biasP ?? 0.0
            guard gainQ.isFinite, gainP.isFinite, biasQ.isFinite, biasP.isFinite else {
                throw CLIInputError.invalidField(
                    "Gate '\(type)' fields gain_q/gain_p/bias_q/bias_p must be finite"
                )
            }
            return .gkpDecodeDisplace(
                on: on,
                valueIndex: valueIndex,
                latticeSpacing: spacing,
                targetLatticeIndex: targetLatticeIndex ?? 0,
                gainQ: gainQ,
                gainP: gainP,
                biasQ: biasQ,
                biasP: biasP,
                mode: try require(mode, "mode")
            )
        case "classical_control", "if_then":
            return .classicalControl(
                on: try require(on, "on"),
                condition: try parseClassicalCondition(),
                apply: try parseClassicalApplyGate()
            )
        default:
            throw CLIInputError.unsupportedGate("Unsupported gate type '\(type)'")
        }
    }

    private func parseNonGaussian(stateLabel: String?) throws -> NonGaussianState {
        guard let label = stateLabel?.lowercased() else {
            throw CLIInputError.missingField("Missing non-Gaussian state label for '\(type)'")
        }

        switch label {
        case "fock":
            return .fock(
                n: try require(n, "n"),
                mode: try require(mode, "mode")
            )
        case "cat":
            return .cat(
                alpha: try require(alpha, "alpha"),
                mode: try require(mode, "mode")
            )
        case "gkp":
            return .gkp(
                delta: try require(delta, "delta"),
                mode: try require(mode, "mode")
            )
        default:
            throw CLIInputError.unsupportedNonGaussian("Unsupported non-Gaussian state '\(label)'")
        }
    }

    private func require<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else {
            throw CLIInputError.missingField("Gate '\(type)' is missing required field '\(name)'")
        }
        return value
    }

    private func parseClassicalCondition() throws -> ClassicalCondition? {
        let hasAny = onValueIndex != nil || onComparator != nil || onThreshold != nil
        guard hasAny else { return nil }

        let valueIndex = try require(onValueIndex, "on_value_index")
        guard valueIndex >= 0 else {
            throw CLIInputError.invalidField("Gate '\(type)' field 'on_value_index' must be >= 0")
        }

        let rawComparator = try require(onComparator, "on_comparator")
        guard let comparator = ClassicalComparator.parse(rawComparator) else {
            throw CLIInputError.invalidField(
                "Unsupported comparator '\(rawComparator)'. Supported: lt, le, gt, ge, eq, ne."
            )
        }

        let threshold = try require(onThreshold, "on_threshold")
        guard threshold.isFinite else {
            throw CLIInputError.invalidField("Gate '\(type)' field 'on_threshold' must be finite")
        }

        return ClassicalCondition(
            valueIndex: valueIndex,
            comparator: comparator,
            threshold: threshold
        )
    }

    private func parseClassicalApplyGate() throws -> Gate {
        guard let applyTypeRaw = applyType else {
            throw CLIInputError.missingField("Gate '\(type)' is missing required field 'apply_type'")
        }

        let applyType = applyTypeRaw.lowercased()
        switch applyType {
        case "phase":
            return .phase(
                theta: try require(applyTheta, "apply_theta"),
                mode: try require(applyMode, "apply_mode")
            )
        case "squeeze":
            return .squeeze(
                r: try require(applyR, "apply_r"),
                mode: try require(applyMode, "apply_mode")
            )
        case "beam_splitter", "beamsplitter":
            return .beamSplitter(
                theta: try require(applyTheta, "apply_theta"),
                modeA: try require(applyModeA, "apply_mode_a"),
                modeB: try require(applyModeB, "apply_mode_b")
            )
        case "displace":
            return .displace(
                q: try require(applyQ, "apply_q"),
                p: try require(applyP, "apply_p"),
                mode: try require(applyMode, "apply_mode")
            )
        default:
            throw CLIInputError.unsupportedGate(
                "Unsupported if_then apply_type '\(applyTypeRaw)'. Supported: phase, squeeze, beam_splitter, displace."
            )
        }
    }
}

struct RunOptions {
    let path: String
    let backendOverride: String?
    let computeBackendOverride: String?
    let cutoffOverride: Int?
    let seedOverride: UInt64?
    let prodMode: Bool
    let foundryRegistryPath: String?
    let foundryKey: String?
}

struct TraceOptions {
    let run: RunOptions
    let role: String
    let rbacPolicyPath: String?
    let traceArtifactPath: String?
    let traceSigningKey: String?
    let maxFrames: Int?
    let ringBuffer: Int?
    let streamFormat: TraceStreamFormat
}

struct BenchmarkOptions {
    let simulationBackend: String
    let computeBackend: ComputeBackend
    let modes: Int
    let layers: Int
    let iterations: Int
    let cutoff: Int
    let seed: UInt64
}

let cliVersion = "1.0.0"
let supportedBackends: Set<String> = ["auto", "gaussian", "fock", "hybrid"]
let supportedComputeBackends: Set<String> = Set(ComputeBackend.allCases.map(\.rawValue))

enum SchemaPolicy {
    static let currentVersion = 1
    static let minSupportedVersion = 1
    static let maxSupportedVersion = 1
}

let defaultFoundryRegistryPath = "config/foundry_registry.json"

enum RuntimeRecommendation {
    static let compiler = "foundry-aware-ir-v1"
    static let contractionPolicy = "hybrid_auto"
    static let gaussianContraction = "symplectic_covariance"
    static let fockContraction = "state_vector_left_to_right"
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64 for deterministic cross-run sampling.
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func resolveSchemaVersion(_ value: Int?) throws -> Int {
    guard let value else {
        throw CLIInputError.missingField("Missing required top-level field 'schema_version'")
    }

    guard value >= SchemaPolicy.minSupportedVersion, value <= SchemaPolicy.maxSupportedVersion else {
        throw CLIInputError.invalidField(
            "Unsupported schema_version '\(value)'. Supported range: \(SchemaPolicy.minSupportedVersion)...\(SchemaPolicy.maxSupportedVersion)"
        )
    }

    return value
}

func deterministicSHA256Hex(of data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func foundryProfileHash(_ spec: FoundrySpec) -> String {
    var payload: [String: Any] = [
        "name": spec.name,
        "allow_non_gaussian": spec.allowNonGaussian,
        "allow_measurements": spec.allowMeasurements,
        "mode_loss_eta": spec.modeLossEta,
        "inject_mode_loss": spec.injectModeLoss
    ]
    payload["max_modes"] = spec.maxModes ?? NSNull()
    payload["max_squeezing_r"] = spec.maxSqueezingR ?? NSNull()

    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
        return "unavailable"
    }
    return deterministicSHA256Hex(of: data)
}

func gitCommitSHA() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "rev-parse", "--short=12", "HEAD"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return "unknown"
    }

    guard process.terminationStatus == 0 else {
        return "unknown"
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let sha = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return sha.isEmpty ? "unknown" : sha
}

func backendVersion(for backend: String) -> String {
    switch backend {
    case "gaussian", "fock":
        return "\(cliVersion)-swift"
    default:
        return "unknown"
    }
}

func contractionType(for backend: String) -> String {
    switch backend {
    case "gaussian":
        return RuntimeRecommendation.gaussianContraction
    case "fock":
        return RuntimeRecommendation.fockContraction
    case "hybrid", "auto":
        return RuntimeRecommendation.contractionPolicy
    default:
        return "unknown"
    }
}

func runGaussian(_ circuit: Circuit, seed: UInt64?) throws -> (finalState: GaussianState, measurements: [MeasurementEvent]) {
    if let seed {
        var rng: any RandomNumberGenerator = SeededGenerator(seed: seed)
        let result = try Simulator.runAndMeasure(circuit, rng: &rng)
        return (result.finalState, result.measurements)
    }

    var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    let result = try Simulator.runAndMeasure(circuit, rng: &rng)
    return (result.finalState, result.measurements)
}

func gaussianStatePayload(_ state: GaussianState) -> [String: Any] {
    [
        "backend": "gaussian",
        "representation": "gaussian_phase_space",
        "modes": state.modes,
        "mean": state.mean,
        "covariance": state.cov
    ]
}

func fockStatePayload(_ state: FockState, topLimit: Int = 12) -> [String: Any] {
    let probabilities = state.psi.map(\.abs2)
    let topProbabilities = probabilities
        .enumerated()
        .sorted { lhs, rhs in
            if lhs.element == rhs.element {
                return lhs.offset < rhs.offset
            }
            return lhs.element > rhs.element
        }
        .prefix(max(topLimit, 1))
        .map { entry in
            [
                "n": entry.offset,
                "probability": entry.element,
                "re": state.psi[entry.offset].re,
                "im": state.psi[entry.offset].im
            ] as [String: Any]
        }

    return [
        "backend": "fock",
        "representation": "fock_number_basis",
        "modes": 1,
        "cutoff": state.cutoff,
        "probabilities": probabilities,
        "top_probabilities": topProbabilities
    ]
}

func gateTypeName(_ gate: Gate) -> String {
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
    case .injectNonGaussian:
        return "inject_non_gaussian"
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

func qecPayload(circuit: Circuit, measurements: [MeasurementEvent]) throws -> [String: Any]? {
    var rounds: [[String: Any]] = []
    rounds.reserveCapacity(circuit.gates.count)

    for (gateIndex, gate) in circuit.gates.enumerated() {
        guard case .gkpDecodeDisplace(
            let on,
            let valueIndex,
            let latticeSpacing,
            let targetLatticeIndex,
            let gainQ,
            let gainP,
            let biasQ,
            let biasP,
            let mode
        ) = gate else {
            continue
        }

        guard on >= 0, on < measurements.count else {
            throw CLIInputError.invalidField(
                "gkp_decode_displace refers to non-existent measurement index '\(on)'"
            )
        }
        let measurement = measurements[on]
        guard valueIndex >= 0, valueIndex < measurement.values.count else {
            throw CLIInputError.invalidField(
                "gkp_decode_displace measurement \(on) does not contain value index \(valueIndex)"
            )
        }
        let syndromeValue = measurement.values[valueIndex]
        let decoded = GKPNearestLatticeDecoder.decode(
            syndromeValue: syndromeValue,
            latticeSpacing: latticeSpacing,
            targetLatticeIndex: targetLatticeIndex
        )
        let appliedQ = gainQ * decoded.correction + biasQ
        let appliedP = gainP * decoded.correction + biasP

        rounds.append([
            "round": rounds.count + 1,
            "gate_index": gateIndex,
            "measurement_index": on,
            "source_value_index": valueIndex,
            "mode": mode,
            "syndrome_value": syndromeValue,
            "decoder": "gkp_nearest_lattice_rounding",
            "lattice_spacing": decoded.latticeSpacing,
            "target_lattice_index": decoded.targetLatticeIndex,
            "nearest_lattice_index": decoded.nearestLatticeIndex,
            "nearest_lattice_value": decoded.nearestLatticeValue,
            "residual": decoded.residual,
            "correction_value": decoded.correction,
            "applied_q": appliedQ,
            "applied_p": appliedP,
            "logical_pass": decoded.logicalPass
        ])
    }

    guard !rounds.isEmpty else { return nil }
    let logicalPassCount = rounds.reduce(into: 0) { partialResult, item in
        if (item["logical_pass"] as? Bool) == true {
            partialResult += 1
        }
    }
    let logicalFailCount = rounds.count - logicalPassCount
    let logicalErrorRate = rounds.isEmpty ? 0.0 : Double(logicalFailCount) / Double(rounds.count)
    let physicalErrorRateProxy = qecPhysicalErrorRateProxy(rounds: rounds)
    let suppressionFactor = qecSuppressionFactor(
        physicalErrorRateProxy: physicalErrorRateProxy,
        logicalErrorRate: logicalErrorRate
    )
    let breakEvenGain = qecBreakEvenGain(
        physicalErrorRateProxy: physicalErrorRateProxy,
        logicalErrorRate: logicalErrorRate
    )
    return [
        "decoder": "gkp_nearest_lattice_rounding",
        "rounds_executed": rounds.count,
        "logical_pass_count": logicalPassCount,
        "logical_fail_count": logicalFailCount,
        "logical_pass": logicalFailCount == 0,
        "logical_error_rate": logicalErrorRate,
        "physical_error_rate_proxy": physicalErrorRateProxy as Any,
        "suppression_factor": suppressionFactor as Any,
        "break_even_gain": breakEvenGain as Any,
        "break_even_pass": (breakEvenGain ?? -Double.infinity) >= 0.0,
        "rounds": rounds
    ]
}

private func qecPhysicalErrorRateProxy(rounds: [[String: Any]]) -> Double? {
    var validCount = 0
    var flaggedCount = 0

    for round in rounds {
        guard let syndromeValue = round["syndrome_value"] as? Double,
              let latticeSpacing = round["lattice_spacing"] as? Double,
              latticeSpacing > 0,
              let targetLatticeIndex = round["target_lattice_index"] as? Int
        else {
            continue
        }

        validCount += 1
        let targetCenter = Double(targetLatticeIndex) * latticeSpacing
        let threshold = 0.25 * latticeSpacing
        if abs(syndromeValue - targetCenter) >= threshold {
            flaggedCount += 1
        }
    }

    guard validCount > 0 else { return nil }
    return Double(flaggedCount) / Double(validCount)
}

private func qecSuppressionFactor(
    physicalErrorRateProxy: Double?,
    logicalErrorRate: Double
) -> Double? {
    guard let physicalErrorRateProxy,
          physicalErrorRateProxy.isFinite,
          logicalErrorRate.isFinite,
          logicalErrorRate >= 0,
          physicalErrorRateProxy >= 0
    else {
        return nil
    }

    if logicalErrorRate == 0 {
        return physicalErrorRateProxy > 0 ? 1_000_000.0 : nil
    }
    return physicalErrorRateProxy / logicalErrorRate
}

private func qecBreakEvenGain(
    physicalErrorRateProxy: Double?,
    logicalErrorRate: Double
) -> Double? {
    guard let physicalErrorRateProxy,
          physicalErrorRateProxy.isFinite,
          logicalErrorRate.isFinite
    else {
        return nil
    }
    return physicalErrorRateProxy - logicalErrorRate
}

func emitJSON(_ payload: [String: Any]) {
    do {
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        FileHandle.standardOutput.write(
            Data("{\"status\":\"error\",\"error\":\"Failed to encode JSON output\"}\n".utf8)
        )
    }
}

func usagePayload() -> [String: Any] {
    [
        "status": "error",
        "error": "Missing or invalid command",
        "usage": [
            "schrosim-cli [--wait-debugger] version",
            "schrosim-cli [--wait-debugger] info",
            "schrosim-cli [--wait-debugger] run <file> [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>]",
            "schrosim-cli [--wait-debugger] trace <file> [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>] [--trace-role <role>] [--trace-rbac <file>] [--trace-artifact <file>] [--trace-key <key>] [--max-frames <n>] [--ring-buffer <n>]",
            "schrosim-cli [--wait-debugger] trace-stream <file> [--stream-format <ndjson|sse>] [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>] [--trace-role <role>] [--trace-rbac <file>]",
            "schrosim-cli [--wait-debugger] trace-share <artifact_file> [--trace-role <role>] [--trace-rbac <file>] [--trace-key <key>] [--target <target>]",
            "schrosim-cli [--wait-debugger] benchmark [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--modes <n>] [--layers <n>] [--iterations <n>] [--cutoff <n>] [--seed <uint64>]",
            "schrosim-cli [--wait-debugger] foundry-admin <add-draft|promote> ..."
        ]
    ]
}

func waitForDebuggerIfRequested(args: inout [String]) {
    guard let idx = args.firstIndex(of: "--wait-debugger") else {
        return
    }

    args.remove(at: idx)
    let pid = getpid()
    fputs("schrosim-cli waiting for debugger attach (pid \(pid)). Resume with Continue.\n", stderr)
    raise(SIGSTOP)
}

func handleVersion() -> Int32 {
    emitJSON([
        "command": "version",
        "status": "success",
        "version": cliVersion
    ])
    return 0
}

func handleInfo() -> Int32 {
    let info: [String: Any] = [
        "command": "info",
        "status": "success",
        "version": cliVersion,
        "schema": [
            "current_version": SchemaPolicy.currentVersion,
            "min_supported_version": SchemaPolicy.minSupportedVersion,
            "max_supported_version": SchemaPolicy.maxSupportedVersion,
            "policy": "exact_match"
        ],
        "backends": [
            "gaussian": true,
            "fock": true,
            "hybrid": true
        ],
        "compute_backends": ComputeBackend.allCases.map(\.rawValue),
        "features": [
            "measurement": true,
            "feedforward": true,
            "noise": ["loss", "thermal"],
            "foundry": true,
            "trace": true,
            "trace_stream": ["ndjson", "sse"],
            "trace_artifact_signing": "hmac-sha256",
            "trace_rbac": true,
            "trace_downsampling": true,
            "trace_ring_buffer": true,
            "compute_backend_selection": true,
            "compute_backend_metal_available": ComputeBackendResolver.metalExecutionAvailable,
            "benchmark": true,
            "foundry_registry": true,
            "foundry_signing": "hmac-sha256"
        ],
        "recommendations": [
            "compiler": RuntimeRecommendation.compiler,
            "contraction_policy": RuntimeRecommendation.contractionPolicy,
            "gaussian_contraction": RuntimeRecommendation.gaussianContraction,
            "fock_contraction": RuntimeRecommendation.fockContraction
        ]
    ]

    emitJSON(info)
    return 0
}

func parseRunOptions(arguments: [String]) throws -> RunOptions {
    var idx = 0
    var path: String?
    var backendOverride: String?
    var computeBackendOverride: String?
    var cutoffOverride: Int?
    var seedOverride: UInt64?
    var prodMode = false
    var foundryRegistryPath: String?
    var foundryKey: String?

    while idx < arguments.count {
        let token = arguments[idx]
        switch token {
        case "--backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --backend")
            }
            backendOverride = arguments[next]
            idx += 2
        case "--compute-backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --compute-backend")
            }
            computeBackendOverride = arguments[next]
            idx += 2
        case "--cutoff":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --cutoff")
            }
            guard let cutoff = Int(arguments[next]), cutoff > 0 else {
                throw CLIInputError.invalidField("Cutoff must be a positive integer")
            }
            cutoffOverride = cutoff
            idx += 2
        case "--seed":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --seed")
            }
            guard let seed = UInt64(arguments[next]) else {
                throw CLIInputError.invalidField("Seed must be an unsigned 64-bit integer")
            }
            seedOverride = seed
            idx += 2
        case "--prod":
            prodMode = true
            idx += 1
        case "--foundry-registry":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --foundry-registry")
            }
            foundryRegistryPath = arguments[next]
            idx += 2
        case "--foundry-key":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --foundry-key")
            }
            foundryKey = arguments[next]
            idx += 2
        default:
            if token.hasPrefix("--") {
                throw CLIInputError.invalidArguments("Unknown option '\(token)'")
            }
            if path == nil {
                path = token
            } else {
                throw CLIInputError.invalidArguments("Only one input file is allowed")
            }
            idx += 1
        }
    }

    guard let path else {
        throw CLIInputError.invalidArguments("Missing input file")
    }
    return RunOptions(
        path: path,
        backendOverride: backendOverride,
        computeBackendOverride: computeBackendOverride,
        cutoffOverride: cutoffOverride,
        seedOverride: seedOverride,
        prodMode: prodMode,
        foundryRegistryPath: foundryRegistryPath,
        foundryKey: foundryKey
    )
}

func parseTraceOptions(arguments: [String], defaultStreamFormat: TraceStreamFormat) throws -> TraceOptions {
    var idx = 0
    var path: String?
    var backendOverride: String?
    var computeBackendOverride: String?
    var cutoffOverride: Int?
    var seedOverride: UInt64?
    var prodMode = false
    var foundryRegistryPath: String?
    var foundryKey: String?
    var role = "viewer"
    var rbacPolicyPath: String?
    var traceArtifactPath: String?
    var traceSigningKey: String?
    var maxFrames: Int?
    var ringBuffer: Int?
    var streamFormatRaw: String?

    while idx < arguments.count {
        let token = arguments[idx]
        switch token {
        case "--backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --backend")
            }
            backendOverride = arguments[next]
            idx += 2
        case "--compute-backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --compute-backend")
            }
            computeBackendOverride = arguments[next]
            idx += 2
        case "--cutoff":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --cutoff")
            }
            guard let cutoff = Int(arguments[next]), cutoff > 0 else {
                throw CLIInputError.invalidField("Cutoff must be a positive integer")
            }
            cutoffOverride = cutoff
            idx += 2
        case "--seed":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --seed")
            }
            guard let seed = UInt64(arguments[next]) else {
                throw CLIInputError.invalidField("Seed must be an unsigned 64-bit integer")
            }
            seedOverride = seed
            idx += 2
        case "--prod":
            prodMode = true
            idx += 1
        case "--foundry-registry":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --foundry-registry")
            }
            foundryRegistryPath = arguments[next]
            idx += 2
        case "--foundry-key":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --foundry-key")
            }
            foundryKey = arguments[next]
            idx += 2
        case "--trace-role":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --trace-role")
            }
            role = arguments[next]
            idx += 2
        case "--trace-rbac":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --trace-rbac")
            }
            rbacPolicyPath = arguments[next]
            idx += 2
        case "--trace-artifact":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --trace-artifact")
            }
            traceArtifactPath = arguments[next]
            idx += 2
        case "--trace-key":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --trace-key")
            }
            traceSigningKey = arguments[next]
            idx += 2
        case "--max-frames":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --max-frames")
            }
            guard let value = Int(arguments[next]), value > 0 else {
                throw CLIInputError.invalidField("--max-frames must be a positive integer")
            }
            maxFrames = value
            idx += 2
        case "--ring-buffer":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --ring-buffer")
            }
            guard let value = Int(arguments[next]), value > 0 else {
                throw CLIInputError.invalidField("--ring-buffer must be a positive integer")
            }
            ringBuffer = value
            idx += 2
        case "--stream-format":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --stream-format")
            }
            streamFormatRaw = arguments[next]
            idx += 2
        default:
            if token.hasPrefix("--") {
                throw CLIInputError.invalidArguments("Unknown option '\(token)'")
            }
            if path == nil {
                path = token
            } else {
                throw CLIInputError.invalidArguments("Only one input file is allowed")
            }
            idx += 1
        }
    }

    guard let path else {
        throw CLIInputError.invalidArguments("Missing input file")
    }
    let streamFormat = try parseTraceStreamFormat(streamFormatRaw ?? defaultStreamFormat.rawValue)
    let run = RunOptions(
        path: path,
        backendOverride: backendOverride,
        computeBackendOverride: computeBackendOverride,
        cutoffOverride: cutoffOverride,
        seedOverride: seedOverride,
        prodMode: prodMode,
        foundryRegistryPath: foundryRegistryPath,
        foundryKey: foundryKey
    )
    return TraceOptions(
        run: run,
        role: role,
        rbacPolicyPath: rbacPolicyPath,
        traceArtifactPath: traceArtifactPath,
        traceSigningKey: traceSigningKey,
        maxFrames: maxFrames,
        ringBuffer: ringBuffer,
        streamFormat: streamFormat
    )
}

func parseBenchmarkOptions(arguments: [String]) throws -> BenchmarkOptions {
    var idx = 0
    var simulationBackend = "gaussian"
    var computeBackendRaw = ComputeBackend.auto.rawValue
    var modes = 4
    var layers = 48
    var iterations = 5
    var cutoff = 20
    var seed: UInt64 = 7

    while idx < arguments.count {
        let token = arguments[idx]
        switch token {
        case "--backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --backend")
            }
            simulationBackend = arguments[next].lowercased()
            idx += 2
        case "--compute-backend":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --compute-backend")
            }
            computeBackendRaw = arguments[next].lowercased()
            idx += 2
        case "--modes":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --modes")
            }
            guard let parsed = Int(arguments[next]), parsed > 0 else {
                throw CLIInputError.invalidField("--modes must be a positive integer")
            }
            modes = parsed
            idx += 2
        case "--layers":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --layers")
            }
            guard let parsed = Int(arguments[next]), parsed > 0 else {
                throw CLIInputError.invalidField("--layers must be a positive integer")
            }
            layers = parsed
            idx += 2
        case "--iterations":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --iterations")
            }
            guard let parsed = Int(arguments[next]), parsed > 0 else {
                throw CLIInputError.invalidField("--iterations must be a positive integer")
            }
            iterations = parsed
            idx += 2
        case "--cutoff":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --cutoff")
            }
            guard let parsed = Int(arguments[next]), parsed > 0 else {
                throw CLIInputError.invalidField("--cutoff must be a positive integer")
            }
            cutoff = parsed
            idx += 2
        case "--seed":
            let next = idx + 1
            guard next < arguments.count else {
                throw CLIInputError.invalidArguments("Missing value for --seed")
            }
            guard let parsed = UInt64(arguments[next]) else {
                throw CLIInputError.invalidField("Seed must be an unsigned 64-bit integer")
            }
            seed = parsed
            idx += 2
        default:
            throw CLIInputError.invalidArguments("Unknown option '\(token)'")
        }
    }

    guard supportedBackends.contains(simulationBackend) else {
        throw CLIInputError.invalidField("Unsupported backend '\(simulationBackend)'")
    }

    guard supportedComputeBackends.contains(computeBackendRaw),
          let computeBackend = ComputeBackend(rawValue: computeBackendRaw) else {
        throw CLIInputError.invalidField("Unsupported compute backend '\(computeBackendRaw)'")
    }

    if simulationBackend == "fock", modes != 1 {
        throw CLIInputError.invalidField("Fock benchmark requires --modes 1")
    }

    return BenchmarkOptions(
        simulationBackend: simulationBackend,
        computeBackend: computeBackend,
        modes: modes,
        layers: layers,
        iterations: iterations,
        cutoff: cutoff,
        seed: seed
    )
}

func meanPhotonNumber(_ state: GaussianState) -> Double {
    var total = 0.0
    for mode in 0..<state.modes {
        let iq = 2 * mode
        let ip = iq + 1
        let q = state.mean[iq]
        let p = state.mean[ip]
        let vq = state.cov[iq][iq]
        let vp = state.cov[ip][ip]
        total += 0.5 * (q * q + p * p + vq + vp - 1.0)
    }
    return max(0.0, total)
}

func buildCircuit(from input: CircuitInput) throws -> Circuit {
    let circuit = try Circuit(modes: input.modes)
    for gateInput in input.gates {
        try circuit.append(try gateInput.toGate())
    }
    return circuit
}

func inferredLossEta(from gates: [Gate]) -> Double? {
    var eta: Double?
    for gate in gates {
        switch gate {
        case .loss(let value, _):
            eta = value
        case .thermalLoss(let value, _, _):
            eta = value
        default:
            continue
        }
    }
    return eta
}

func computeWorkloadProfile(from circuit: Circuit) -> ComputeWorkloadProfile {
    var includesFockPath = false
    var includesMeasurements = false
    for gate in circuit.gates {
        switch gate {
        case .injectNonGaussian(let ng):
            switch ng {
            case .fock, .cat:
                includesFockPath = true
            case .gkp:
                break
            }
        case .measureHomodyne, .measureHeterodyne:
            includesMeasurements = true
        case .feedbackDisplace:
            includesMeasurements = true
        case .gkpDecodeDisplace:
            includesMeasurements = true
        default:
            break
        }
    }

    return ComputeWorkloadProfile(
        modes: circuit.modes,
        gateCount: circuit.gates.count,
        includesFockPath: includesFockPath,
        includesMeasurements: includesMeasurements
    )
}

func resolveComputeBackend(
    requestedRaw: String?,
    circuit: Circuit
) throws -> ComputeBackendResolution {
    let requestedValue = (requestedRaw ?? ComputeBackend.auto.rawValue).lowercased()
    guard supportedComputeBackends.contains(requestedValue),
          let requested = ComputeBackend(rawValue: requestedValue) else {
        throw CLIInputError.invalidField("Unsupported compute backend '\(requestedValue)'")
    }

    let workload = computeWorkloadProfile(from: circuit)
    return ComputeBackendResolver.resolve(requested: requested, workload: workload)
}

struct ResolvedFoundryRuntime {
    let spec: FoundrySpec
    let source: String
    let profileID: String?
    let profileVersion: Int?
    let profileStatus: String?
}

struct TraceExecutionResult {
    let backendUsed: String
    let meanPhoton: Double
    let measurementCount: Int
    let frames: TraceFrameCollectionResult
    let totalTraceMs: Double
    let finalStatePayload: [String: Any]
    let qecPayload: [String: Any]?
}

struct RunExecutionResult {
    let backendUsed: String
    let meanPhoton: Double
    let measurementCount: Int
    let finalStatePayload: [String: Any]
    let qecPayload: [String: Any]?
}

func resolveFoundryRuntime(input: CircuitInput, options: RunOptions) throws -> ResolvedFoundryRuntime {
    if input.foundry != nil && input.foundryProfile != nil {
        throw CLIInputError.invalidField("Only one of 'foundry' or 'foundry_profile' may be provided")
    }

    if options.prodMode, input.foundry != nil {
        throw CLIInputError.invalidField("Inline 'foundry' block is not allowed in --prod mode; use 'foundry_profile'")
    }

    if let profileRef = input.foundryProfile {
        let trimmedID = profileRef.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw CLIInputError.invalidField("'foundry_profile.profile_id' must not be empty")
        }
        guard profileRef.version > 0 else {
            throw CLIInputError.invalidField("'foundry_profile.version' must be a positive integer")
        }

        let registryPath = options.foundryRegistryPath ?? defaultFoundryRegistryPath
        let signingKey = options.foundryKey
            ?? ProcessInfo.processInfo.environment["SCHROSIM_FOUNDRY_HMAC_KEY"]

        guard let signingKey, !signingKey.isEmpty else {
            throw CLIInputError.missingField(
                "Missing foundry signing key. Provide --foundry-key or SCHROSIM_FOUNDRY_HMAC_KEY"
            )
        }

        let resolved = try resolveFoundryProfileFromRegistry(
            registryPath: registryPath,
            profileID: trimmedID,
            version: profileRef.version,
            signingKey: signingKey,
            now: Date()
        )

        return ResolvedFoundryRuntime(
            spec: resolved.spec.toFoundrySpec(defaultName: resolved.profileID),
            source: "registry",
            profileID: resolved.profileID,
            profileVersion: resolved.version,
            profileStatus: resolved.status.rawValue
        )
    }

    if options.prodMode {
        throw CLIInputError.missingField("Missing required top-level field 'foundry_profile' in --prod mode")
    }

    if let foundryInput = input.foundry {
        return ResolvedFoundryRuntime(
            spec: foundryInput.toSpec(defaultName: "runtime-input"),
            source: "input",
            profileID: nil,
            profileVersion: nil,
            profileStatus: nil
        )
    }

    throw CLIInputError.missingField("Missing required top-level field 'foundry' or 'foundry_profile'")
}

func executeTrace(
    circuit: Circuit,
    requestedBackend: String,
    computeBackend: ComputeBackend,
    cutoff: Int,
    seed: UInt64?,
    maxFrames: Int?,
    ringBuffer: Int?,
    onFrame: ((TraceFrameRecord) -> Void)? = nil
) throws -> TraceExecutionResult {
    return try ComputeExecutionContext.withBackend(computeBackend) {
        var collector = TraceFrameCollector(maxFrames: maxFrames, ringBufferCapacity: ringBuffer)
        let traceStart = CFAbsoluteTimeGetCurrent()

        func acceptFrame(_ frame: TraceFrameRecord) {
            collector.append(frame)
            onFrame?(frame)
        }

        let backendUsed: String
        let meanPhoton: Double
        let measurementCount: Int
        let finalStatePayload: [String: Any]
        let qecReport: [String: Any]?

        let resolvedBackend = try BackendRouting.resolveExecutionBackend(
            requestedBackend: requestedBackend,
            circuit: circuit
        )

        switch resolvedBackend {
        case "gaussian":
            backendUsed = "gaussian"
            var frameIndex = 1
            if let seed {
                var rng: any RandomNumberGenerator = SeededGenerator(seed: seed)
                let result = try Simulator.runAndMeasureStreaming(circuit, rng: &rng) { frame in
                    acceptFrame(
                        TraceFrameRecord(
                            frameIndex: frameIndex,
                            gateIndex: frame.gateIndex,
                            gateType: gateTypeName(frame.gate),
                            meanPhotonNumber: frame.meanPhotonNumber,
                            measurementCount: frame.measurementCount,
                            frameLatencyMs: frame.frameLatencyMs
                        )
                    )
                    frameIndex += 1
                }
                meanPhoton = meanPhotonNumber(result.finalState)
                measurementCount = result.measurements.count
                finalStatePayload = gaussianStatePayload(result.finalState)
                qecReport = try qecPayload(circuit: circuit, measurements: result.measurements)
            } else {
                var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
                let result = try Simulator.runAndMeasureStreaming(circuit, rng: &rng) { frame in
                    acceptFrame(
                        TraceFrameRecord(
                            frameIndex: frameIndex,
                            gateIndex: frame.gateIndex,
                            gateType: gateTypeName(frame.gate),
                            meanPhotonNumber: frame.meanPhotonNumber,
                            measurementCount: frame.measurementCount,
                            frameLatencyMs: frame.frameLatencyMs
                        )
                    )
                    frameIndex += 1
                }
                meanPhoton = meanPhotonNumber(result.finalState)
                measurementCount = result.measurements.count
                finalStatePayload = gaussianStatePayload(result.finalState)
                qecReport = try qecPayload(circuit: circuit, measurements: result.measurements)
            }

        case "fock":
            backendUsed = "fock"
            var frameIndex = 1
            let result = try FockBackend.runStreaming(circuit, cutoff: cutoff) { frame in
                acceptFrame(
                    TraceFrameRecord(
                        frameIndex: frameIndex,
                        gateIndex: frame.gateIndex,
                        gateType: gateTypeName(frame.gate),
                        meanPhotonNumber: frame.meanPhotonNumber,
                        measurementCount: 0,
                        frameLatencyMs: frame.frameLatencyMs
                    )
                )
                frameIndex += 1
            }
            meanPhoton = result.final.expectedPhotonNumber()
            measurementCount = 0
            finalStatePayload = fockStatePayload(result.final)
            qecReport = nil

        default:
            throw CLIInputError.invalidField("Unsupported backend '\(resolvedBackend)'")
        }

        let totalTraceMs = max(0.0, (CFAbsoluteTimeGetCurrent() - traceStart) * 1000.0)
        var collected = collector.finish()

        let initialFrame = TraceFrameRecord(
            frameIndex: 0,
            gateIndex: nil,
            gateType: "initial",
            meanPhotonNumber: 0.0,
            measurementCount: 0,
            frameLatencyMs: 0.0
        )

        collected = TraceFrameCollectionResult(
            frames: [initialFrame] + collected.frames,
            originalCount: collected.originalCount + 1,
            droppedCount: collected.droppedCount,
            downsampleApplied: collected.downsampleApplied,
            ringBufferApplied: collected.ringBufferApplied,
            maxFrameLatencyMs: collected.maxFrameLatencyMs
        )

        return TraceExecutionResult(
            backendUsed: backendUsed,
            meanPhoton: meanPhoton,
            measurementCount: measurementCount,
            frames: collected,
            totalTraceMs: totalTraceMs,
            finalStatePayload: finalStatePayload,
            qecPayload: qecReport
        )
    }
}

func executeRun(
    circuit: Circuit,
    requestedBackend: String,
    computeBackend: ComputeBackend,
    cutoff: Int,
    seed: UInt64?
) throws -> RunExecutionResult {
    try ComputeExecutionContext.withBackend(computeBackend) {
        let resolvedBackend = try BackendRouting.resolveExecutionBackend(
            requestedBackend: requestedBackend,
            circuit: circuit
        )

        switch resolvedBackend {
        case "gaussian":
            let result = try runGaussian(circuit, seed: seed)
            return RunExecutionResult(
                backendUsed: "gaussian",
                meanPhoton: meanPhotonNumber(result.finalState),
                measurementCount: result.measurements.count,
                finalStatePayload: gaussianStatePayload(result.finalState),
                qecPayload: try qecPayload(circuit: circuit, measurements: result.measurements)
            )
        case "fock":
            let result = try FockBackend.run(circuit, cutoff: cutoff)
            return RunExecutionResult(
                backendUsed: "fock",
                meanPhoton: result.final.expectedPhotonNumber(),
                measurementCount: 0,
                finalStatePayload: fockStatePayload(result.final),
                qecPayload: nil
            )
        default:
            throw CLIInputError.invalidField("Unsupported backend '\(resolvedBackend)'")
        }
    }
}

func buildBenchmarkCircuit(options: BenchmarkOptions) throws -> Circuit {
    let circuit = try Circuit(modes: options.modes)

    if options.simulationBackend == "fock" {
        for layer in 0..<options.layers {
            let theta = 0.008 * Double((layer % 17) + 1)
            let q = 0.004 * Double((layer % 11) + 1)
            let p = -0.003 * Double((layer % 7) + 1)
            try circuit.append(.phase(theta: theta, mode: 0))
            try circuit.append(.displace(q: q, p: p, mode: 0))
        }
        return circuit
    }

    for layer in 0..<options.layers {
        for mode in 0..<options.modes {
            let theta = 0.006 * Double(((layer + mode) % 13) + 1)
            let q = 0.003 * Double(((layer + 2 * mode) % 9) + 1)
            let p = -0.0025 * Double(((2 * layer + mode) % 7) + 1)
            try circuit.append(.phase(theta: theta, mode: mode))
            try circuit.append(.displace(q: q, p: p, mode: mode))
            if (layer + mode) % 3 == 0 {
                let squeezeR = 0.03 * Double(((layer + mode) % 4) + 1)
                try circuit.append(.squeeze(r: squeezeR, mode: mode))
            }
        }

        if options.modes > 1 {
            for modeA in 0..<(options.modes - 1) {
                let theta = 0.1 + 0.01 * Double((layer + modeA) % 5)
                try circuit.append(.beamSplitter(theta: theta, modeA: modeA, modeB: modeA + 1))
            }
        }
    }

    try circuit.append(.measureHomodyne(mode: 0, theta: 0.0))
    return circuit
}

func percentile(_ sortedSamples: [Double], p: Double) -> Double {
    guard !sortedSamples.isEmpty else { return 0.0 }
    if sortedSamples.count == 1 { return sortedSamples[0] }

    let clamped = max(0.0, min(1.0, p))
    let position = clamped * Double(sortedSamples.count - 1)
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper { return sortedSamples[lower] }

    let w = position - Double(lower)
    return sortedSamples[lower] * (1.0 - w) + sortedSamples[upper] * w
}

func latencyStats(samples: [Double]) -> (min: Double, p50: Double, p95: Double, avg: Double, max: Double) {
    guard !samples.isEmpty else {
        return (0.0, 0.0, 0.0, 0.0, 0.0)
    }

    let sorted = samples.sorted()
    let total = sorted.reduce(0.0, +)
    return (
        sorted.first ?? 0.0,
        percentile(sorted, p: 0.5),
        percentile(sorted, p: 0.95),
        total / Double(sorted.count),
        sorted.last ?? 0.0
    )
}

func handleBenchmark(arguments: [String]) -> Int32 {
    let options: BenchmarkOptions
    do {
        options = try parseBenchmarkOptions(arguments: arguments)
    } catch {
        emitJSON([
            "command": "benchmark",
            "status": "error",
            "error": String(describing: error),
            "usage": "schrosim-cli [--wait-debugger] benchmark [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--modes <n>] [--layers <n>] [--iterations <n>] [--cutoff <n>] [--seed <uint64>]"
        ])
        return 1
    }

    do {
        let circuit = try buildBenchmarkCircuit(options: options)
        let computeResolution = ComputeBackendResolver.resolve(
            requested: options.computeBackend,
            workload: computeWorkloadProfile(from: circuit)
        )

        var latenciesMs: [Double] = []
        latenciesMs.reserveCapacity(options.iterations)
        var backendUsed = options.simulationBackend
        var meanPhoton = 0.0
        var measurementCount = 0

        for iteration in 0..<options.iterations {
            let seed = options.seed &+ UInt64(iteration)
            let start = CFAbsoluteTimeGetCurrent()
            let execution = try executeRun(
                circuit: circuit,
                requestedBackend: options.simulationBackend,
                computeBackend: computeResolution.used,
                cutoff: options.cutoff,
                seed: seed
            )
            let elapsedMs = max(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0)

            latenciesMs.append(elapsedMs)
            backendUsed = execution.backendUsed
            meanPhoton = execution.meanPhoton
            measurementCount = execution.measurementCount
        }

        let stats = latencyStats(samples: latenciesMs)
        let gatesPerSecondAvg = stats.avg > 0.0 ? (Double(circuit.gates.count) / (stats.avg / 1000.0)) : 0.0

        let provenance: [String: Any] = [
            "git_sha": gitCommitSHA(),
            "backend_version": backendVersion(for: backendUsed),
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "seed": String(options.seed)
        ]

        emitJSON([
            "command": "benchmark",
            "status": "success",
            "backend_requested": options.simulationBackend,
            "backend": backendUsed,
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "compiler": RuntimeRecommendation.compiler,
            "contraction_type": contractionType(for: backendUsed),
            "contraction_policy": RuntimeRecommendation.contractionPolicy,
            "modes": options.modes,
            "layers": options.layers,
            "iterations": options.iterations,
            "gate_count": circuit.gates.count,
            "cutoff": options.cutoff,
            "seed": String(options.seed),
            "mean_photon_number": meanPhoton,
            "measurement_count": measurementCount,
            "latency_ms": [
                "min": stats.min,
                "p50": stats.p50,
                "p95": stats.p95,
                "avg": stats.avg,
                "max": stats.max
            ],
            "gates_per_second_avg": gatesPerSecondAvg,
            "latency_samples_ms": latenciesMs,
            "provenance": provenance
        ])
        return 0
    } catch {
        emitJSON([
            "command": "benchmark",
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }
}

func handleRun(arguments: [String]) -> Int32 {
    let options: RunOptions
    do {
        options = try parseRunOptions(arguments: arguments)
    } catch {
        emitJSON([
            "command": "run",
            "status": "error",
            "error": String(describing: error),
            "usage": "schrosim-cli [--wait-debugger] run <file> [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>]"
        ])
        return 1
    }

    do {
        let url = URL(fileURLWithPath: options.path)
        let data = try Data(contentsOf: url)
        let input = try JSONDecoder().decode(CircuitInput.self, from: data)
        let schemaVersion = try resolveSchemaVersion(input.schemaVersion)
        let sourceCircuit = try buildCircuit(from: input)
        let sourceGateCount = sourceCircuit.gates.count
        let resolvedSeed = options.seedOverride ?? input.seed
        let foundryRuntime = try resolveFoundryRuntime(input: input, options: options)
        let foundrySpec = foundryRuntime.spec
        let circuit = try FoundryCompiler.compile(sourceCircuit, with: foundrySpec)
        let requestedBackend = (options.backendOverride ?? input.backend ?? "auto").lowercased()
        let computeResolution = try resolveComputeBackend(
            requestedRaw: options.computeBackendOverride,
            circuit: circuit
        )

        guard supportedBackends.contains(requestedBackend) else {
            emitJSON([
                "command": "run",
                "input": options.path,
                "backend": requestedBackend,
                "compute_backend_requested": computeResolution.requested.rawValue,
                "compute_backend_candidate": computeResolution.candidate.rawValue,
                "compute_backend_used": computeResolution.used.rawValue,
                "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
                "status": "error",
                "error": "Unsupported backend '\(requestedBackend)'"
            ])
            return 1
        }

        let cutoff = options.cutoffOverride ?? input.cutoff ?? 20
        guard cutoff > 0 else {
            throw CLIInputError.invalidField("Cutoff must be a positive integer")
        }

        let execution = try executeRun(
            circuit: circuit,
            requestedBackend: requestedBackend,
            computeBackend: computeResolution.used,
            cutoff: cutoff,
            seed: resolvedSeed
        )
        let backendUsed = execution.backendUsed
        let meanPhoton = execution.meanPhoton
        let measurementCount = execution.measurementCount

        let provenance: [String: Any] = [
            "foundry_profile_hash": foundryProfileHash(foundrySpec),
            "git_sha": gitCommitSHA(),
            "backend_version": backendVersion(for: backendUsed),
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "seed": resolvedSeed.map(String.init) ?? NSNull(),
            "profile_id": foundryRuntime.profileID ?? NSNull(),
            "profile_version": foundryRuntime.profileVersion ?? NSNull(),
            "profile_status": foundryRuntime.profileStatus ?? NSNull()
        ]

        var result: [String: Any] = [
            "command": "run",
            "input": options.path,
            "schema_version": schemaVersion,
            "backend": backendUsed,
            "backend_requested": requestedBackend,
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "compiler": RuntimeRecommendation.compiler,
            "contraction_type": contractionType(for: backendUsed),
            "contraction_policy": RuntimeRecommendation.contractionPolicy,
            "modes": input.modes,
            "gate_count": circuit.gates.count,
            "source_gate_count": sourceGateCount,
            "foundry": foundrySpec.name,
            "foundry_source": foundryRuntime.source,
            "foundry_injected_gate_count": max(0, circuit.gates.count - sourceGateCount),
            "mean_photon_number": meanPhoton,
            "measurement_count": measurementCount,
            "final_state": execution.finalStatePayload,
            "cutoff": cutoff,
            "provenance": provenance,
            "status": "success"
        ]

        if let eta = inferredLossEta(from: circuit.gates) {
            result["loss_eta"] = eta
        }
        if let qec = execution.qecPayload {
            result["qec"] = qec
        }

        emitJSON(result)
        return 0
    } catch {
        emitJSON([
            "command": "run",
            "input": options.path,
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }
}

func handleTrace(arguments: [String]) -> Int32 {
    let options: TraceOptions
    do {
        options = try parseTraceOptions(arguments: arguments, defaultStreamFormat: .ndjson)
    } catch {
        emitJSON([
            "command": "trace",
            "status": "error",
            "error": String(describing: error),
            "usage": "schrosim-cli [--wait-debugger] trace <file> [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>] [--trace-role <role>] [--trace-rbac <file>] [--trace-artifact <file>] [--trace-key <key>] [--max-frames <n>] [--ring-buffer <n>]"
        ])
        return 1
    }

    do {
        try requireTraceRBACAction(role: options.role, action: .view, policyPath: options.rbacPolicyPath)
        if options.traceArtifactPath != nil {
            try requireTraceRBACAction(role: options.role, action: .export, policyPath: options.rbacPolicyPath)
        }

        let url = URL(fileURLWithPath: options.run.path)
        let data = try Data(contentsOf: url)
        let input = try JSONDecoder().decode(CircuitInput.self, from: data)
        let schemaVersion = try resolveSchemaVersion(input.schemaVersion)
        let sourceCircuit = try buildCircuit(from: input)
        let sourceGateCount = sourceCircuit.gates.count
        let resolvedSeed = options.run.seedOverride ?? input.seed
        let foundryRuntime = try resolveFoundryRuntime(input: input, options: options.run)
        let foundrySpec = foundryRuntime.spec
        let circuit = try FoundryCompiler.compile(sourceCircuit, with: foundrySpec)
        let requestedBackend = (options.run.backendOverride ?? input.backend ?? "auto").lowercased()
        let computeResolution = try resolveComputeBackend(
            requestedRaw: options.run.computeBackendOverride,
            circuit: circuit
        )

        guard supportedBackends.contains(requestedBackend) else {
            emitJSON([
                "command": "trace",
                "input": options.run.path,
                "backend": requestedBackend,
                "compute_backend_requested": computeResolution.requested.rawValue,
                "compute_backend_candidate": computeResolution.candidate.rawValue,
                "compute_backend_used": computeResolution.used.rawValue,
                "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
                "status": "error",
                "error": "Unsupported backend '\(requestedBackend)'"
            ])
            return 1
        }

        let cutoff = options.run.cutoffOverride ?? input.cutoff ?? 20
        guard cutoff > 0 else {
            throw CLIInputError.invalidField("Cutoff must be a positive integer")
        }

        let execution = try executeTrace(
            circuit: circuit,
            requestedBackend: requestedBackend,
            computeBackend: computeResolution.used,
            cutoff: cutoff,
            seed: resolvedSeed,
            maxFrames: options.maxFrames,
            ringBuffer: options.ringBuffer
        )

        let provenance: [String: Any] = [
            "foundry_profile_hash": foundryProfileHash(foundrySpec),
            "git_sha": gitCommitSHA(),
            "backend_version": backendVersion(for: execution.backendUsed),
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "seed": resolvedSeed.map(String.init) ?? NSNull(),
            "profile_id": foundryRuntime.profileID ?? NSNull(),
            "profile_version": foundryRuntime.profileVersion ?? NSNull(),
            "profile_status": foundryRuntime.profileStatus ?? NSNull()
        ]

        let replayChecksum = traceReplayChecksum(
            schemaVersion: schemaVersion,
            backend: execution.backendUsed,
            compiler: RuntimeRecommendation.compiler,
            contractionType: contractionType(for: execution.backendUsed),
            foundryProfileHash: foundryProfileHash(foundrySpec),
            seed: resolvedSeed,
            computeBackendRequested: computeResolution.requested.rawValue,
            computeBackendCandidate: computeResolution.candidate.rawValue,
            computeBackendUsed: computeResolution.used.rawValue,
            computeBackendFallbackReason: computeResolution.fallbackReason,
            frames: execution.frames.frames
        )

        let suggestedFrameMs = 120
        var result: [String: Any] = [
            "command": "trace",
            "input": options.run.path,
            "schema_version": schemaVersion,
            "backend": execution.backendUsed,
            "backend_requested": requestedBackend,
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "compiler": RuntimeRecommendation.compiler,
            "contraction_type": contractionType(for: execution.backendUsed),
            "contraction_policy": RuntimeRecommendation.contractionPolicy,
            "modes": input.modes,
            "gate_count": circuit.gates.count,
            "source_gate_count": sourceGateCount,
            "foundry": foundrySpec.name,
            "foundry_source": foundryRuntime.source,
            "foundry_injected_gate_count": max(0, circuit.gates.count - sourceGateCount),
            "mean_photon_number": execution.meanPhoton,
            "measurement_count": execution.measurementCount,
            "final_state": execution.finalStatePayload,
            "cutoff": cutoff,
            "playback_suggested_frame_ms": suggestedFrameMs,
            "trace_frame_count": execution.frames.frames.count,
            "trace_original_frame_count": execution.frames.originalCount,
            "trace_dropped_frame_count": execution.frames.droppedCount,
            "trace_downsampling_applied": execution.frames.downsampleApplied,
            "trace_ring_buffer_applied": execution.frames.ringBufferApplied,
            "trace_total_ms": execution.totalTraceMs,
            "trace_max_frame_latency_ms": execution.frames.maxFrameLatencyMs,
            "frames": execution.frames.frames.map(traceFrameJSONObject),
            "replay_checksum": replayChecksum,
            "provenance": provenance,
            "trace_role": options.role,
            "status": "success"
        ]

        if let eta = inferredLossEta(from: circuit.gates) {
            result["loss_eta"] = eta
        }
        if let qec = execution.qecPayload {
            result["qec"] = qec
        }

        if let artifactPath = options.traceArtifactPath {
            let signingKey = options.traceSigningKey
                ?? ProcessInfo.processInfo.environment["SCHROSIM_TRACE_HMAC_KEY"]
            guard let signingKey, !signingKey.isEmpty else {
                throw TraceEnterpriseError.missingTraceSigningKey
            }

            let envelope = try makeTraceArtifactEnvelope(payload: result, signingKey: signingKey)
            try writeJSONObject(envelope, to: artifactPath)
            result["trace_artifact_path"] = artifactPath
            result["trace_artifact_signed"] = true
            result["trace_artifact_signature"] = (envelope["signature"] as? String) ?? NSNull()
        }

        emitJSON(result)
        return 0
    } catch {
        emitJSON([
            "command": "trace",
            "input": options.run.path,
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }
}

func handleTraceStream(arguments: [String]) -> Int32 {
    let options: TraceOptions
    do {
        options = try parseTraceOptions(arguments: arguments, defaultStreamFormat: .ndjson)
    } catch {
        emitJSON([
            "command": "trace-stream",
            "status": "error",
            "error": String(describing: error),
            "usage": "schrosim-cli [--wait-debugger] trace-stream <file> [--stream-format <ndjson|sse>] [--backend <auto|gaussian|fock|hybrid>] [--compute-backend <auto|cpu|metal>] [--cutoff <n>] [--seed <uint64>] [--prod] [--foundry-registry <file>] [--foundry-key <key>] [--trace-role <role>] [--trace-rbac <file>]"
        ])
        return 1
    }

    do {
        try requireTraceRBACAction(role: options.role, action: .view, policyPath: options.rbacPolicyPath)

        let url = URL(fileURLWithPath: options.run.path)
        let data = try Data(contentsOf: url)
        let input = try JSONDecoder().decode(CircuitInput.self, from: data)
        let schemaVersion = try resolveSchemaVersion(input.schemaVersion)
        let sourceCircuit = try buildCircuit(from: input)
        let sourceGateCount = sourceCircuit.gates.count
        let resolvedSeed = options.run.seedOverride ?? input.seed
        let foundryRuntime = try resolveFoundryRuntime(input: input, options: options.run)
        let foundrySpec = foundryRuntime.spec
        let circuit = try FoundryCompiler.compile(sourceCircuit, with: foundrySpec)
        let requestedBackend = (options.run.backendOverride ?? input.backend ?? "auto").lowercased()
        let computeResolution = try resolveComputeBackend(
            requestedRaw: options.run.computeBackendOverride,
            circuit: circuit
        )

        guard supportedBackends.contains(requestedBackend) else {
            emitJSON([
                "command": "trace-stream",
                "input": options.run.path,
                "backend": requestedBackend,
                "compute_backend_requested": computeResolution.requested.rawValue,
                "compute_backend_candidate": computeResolution.candidate.rawValue,
                "compute_backend_used": computeResolution.used.rawValue,
                "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
                "status": "error",
                "error": "Unsupported backend '\(requestedBackend)'"
            ])
            return 1
        }

        let cutoff = options.run.cutoffOverride ?? input.cutoff ?? 20
        guard cutoff > 0 else {
            throw CLIInputError.invalidField("Cutoff must be a positive integer")
        }

        let meta: [String: Any] = [
            "command": "trace-stream",
            "input": options.run.path,
            "schema_version": schemaVersion,
            "backend_requested": requestedBackend,
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "compiler": RuntimeRecommendation.compiler,
            "contraction_policy": RuntimeRecommendation.contractionPolicy,
            "modes": input.modes,
            "gate_count": circuit.gates.count,
            "source_gate_count": sourceGateCount,
            "foundry": foundrySpec.name,
            "foundry_source": foundryRuntime.source,
            "trace_role": options.role
        ]
        try emitTraceStreamEvent(format: options.streamFormat, event: "meta", payload: meta)

        let initialFrame = TraceFrameRecord(
            frameIndex: 0,
            gateIndex: nil,
            gateType: "initial",
            meanPhotonNumber: 0.0,
            measurementCount: 0,
            frameLatencyMs: 0.0
        )
        try emitTraceStreamEvent(
            format: options.streamFormat,
            event: "frame",
            payload: traceFrameJSONObject(initialFrame)
        )

        var emittedFrames = 1
        var streamEventError: Error?
        let execution = try executeTrace(
            circuit: circuit,
            requestedBackend: requestedBackend,
            computeBackend: computeResolution.used,
            cutoff: cutoff,
            seed: resolvedSeed,
            maxFrames: 1,
            ringBuffer: 1
        ) { frame in
            guard streamEventError == nil else {
                return
            }
            do {
                try emitTraceStreamEvent(format: options.streamFormat, event: "frame", payload: traceFrameJSONObject(frame))
                emittedFrames += 1
            } catch {
                streamEventError = error
            }
        }

        if let streamEventError {
            throw streamEventError
        }

        let done: [String: Any] = [
            "command": "trace-stream",
            "status": "success",
            "backend": execution.backendUsed,
            "compute_backend_requested": computeResolution.requested.rawValue,
            "compute_backend_candidate": computeResolution.candidate.rawValue,
            "compute_backend_used": computeResolution.used.rawValue,
            "compute_backend_fallback_reason": computeResolution.fallbackReason ?? NSNull(),
            "contraction_type": contractionType(for: execution.backendUsed),
            "foundry_injected_gate_count": max(0, circuit.gates.count - sourceGateCount),
            "mean_photon_number": execution.meanPhoton,
            "measurement_count": execution.measurementCount,
            "final_state": execution.finalStatePayload,
            "trace_total_ms": execution.totalTraceMs,
            "trace_max_frame_latency_ms": execution.frames.maxFrameLatencyMs,
            "trace_frame_count": emittedFrames
        ]
        try emitTraceStreamEvent(format: options.streamFormat, event: "done", payload: done)
        return 0
    } catch {
        do {
            try emitTraceStreamEvent(
                format: options.streamFormat,
                event: "error",
                payload: [
                    "command": "trace-stream",
                    "status": "error",
                    "error": String(describing: error)
                ]
            )
        } catch {
            emitJSON([
                "command": "trace-stream",
                "status": "error",
                "error": String(describing: error)
            ])
        }
        return 1
    }
}

func handleTraceShare(arguments: [String]) -> Int32 {
    guard let artifactPath = arguments.first, !artifactPath.hasPrefix("--") else {
        emitJSON([
            "command": "trace-share",
            "status": "error",
            "error": "Missing required artifact path",
            "usage": "schrosim-cli [--wait-debugger] trace-share <artifact_file> [--trace-role <role>] [--trace-rbac <file>] [--trace-key <key>] [--target <target>]"
        ])
        return 1
    }

    let optionsRaw = Array(arguments.dropFirst())
    let options: [String: String]
    do {
        options = try parseFoundryAdminOptions(optionsRaw)
    } catch {
        emitJSON([
            "command": "trace-share",
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }

    do {
        let role = options["trace-role"] ?? "viewer"
        let rbacPolicyPath = options["trace-rbac"]
        try requireTraceRBACAction(role: role, action: .share, policyPath: rbacPolicyPath)

        let envelope = try decodeJSONObject(path: artifactPath)
        let signingKey = options["trace-key"]
            ?? ProcessInfo.processInfo.environment["SCHROSIM_TRACE_HMAC_KEY"]
        let verify = try verifyTraceArtifactEnvelope(envelope, key: signingKey)

        let target = options["target"] ?? "internal"
        let ticketSeed: [String: Any] = [
            "artifact_path": artifactPath,
            "checksum": verify.checksum,
            "target": target,
            "role": role,
            "issued_at": currentISO8601Timestamp()
        ]
        let seedData = try JSONSerialization.data(withJSONObject: ticketSeed, options: [.sortedKeys])
        let shareTicket = deterministicSHA256Hex(of: seedData)

        emitJSON([
            "command": "trace-share",
            "status": "success",
            "artifact_path": artifactPath,
            "target": target,
            "trace_role": role,
            "replay_checksum": verify.checksum,
            "signature_verified": verify.signatureVerified,
            "share_ticket": shareTicket
        ])
        return 0
    } catch {
        emitJSON([
            "command": "trace-share",
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }
}

var args = Array(CommandLine.arguments.dropFirst())
waitForDebuggerIfRequested(args: &args)

guard let commandName = args.first,
      let command = CLICommand(rawValue: commandName) else {
    emitJSON(usagePayload())
    exit(1)
}

let commandArgs = Array(args.dropFirst())
let exitCode: Int32

switch command {
case .version:
    exitCode = handleVersion()
case .info:
    exitCode = handleInfo()
case .run:
    exitCode = handleRun(arguments: commandArgs)
case .trace:
    exitCode = handleTrace(arguments: commandArgs)
case .traceStream:
    exitCode = handleTraceStream(arguments: commandArgs)
case .traceShare:
    exitCode = handleTraceShare(arguments: commandArgs)
case .benchmark:
    exitCode = handleBenchmark(arguments: commandArgs)
case .foundryAdmin:
    exitCode = handleFoundryAdmin(arguments: commandArgs)
}

exit(exitCode)
