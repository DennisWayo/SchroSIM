import Foundation

public enum SimulatorError: Error, CustomStringConvertible {
    case unsupportedGate(Gate)
    case invalidLowering(String)

    public var description: String {
        switch self {
        case .unsupportedGate(let g):
            return "Unsupported gate in current simulator: \(g)"
        case .invalidLowering(let msg):
            return "Invalid lowering: \(msg)"
        }
    }
}

public enum Simulator {

    // NOTE: intentionally NOT Equatable
    public struct SimulationResult: Sendable {
        public let finalState: GaussianState
        public let measurements: [MeasurementEvent]
    }

    public static func runAndMeasure(
        _ circuit: Circuit,
        initial: GaussianState? = nil,
        rng: inout any RandomNumberGenerator
    ) throws -> SimulationResult {

        var state = initial ?? GaussianState.vacuum(modes: circuit.modes)

        guard state.modes == circuit.modes else {
            throw SimulatorError.invalidLowering(
                "Initial state modes \(state.modes) != circuit modes \(circuit.modes)"
            )
        }

        var events: [MeasurementEvent] = []

        for (idx, g) in circuit.gates.enumerated() {
            switch g {

            // --- Measurements (sample + condition) ---

            case .measureHomodyne(let mode, let theta):
                let (y, post) = try GaussianMeasurement.sampleHomodyne(
                    from: state, mode: mode, theta: theta, rng: &rng
                )
                state = post
                events.append(
                    MeasurementEvent(
                        index: idx,
                        mode: mode,
                        kind: .homodyne(theta: theta),
                        values: [y]
                    )
                )

            case .measureHeterodyne(let mode):
                let (qp, post) = try GaussianMeasurement.sampleHeterodyne(
                    from: state, mode: mode, rng: &rng
                )
                state = post
                events.append(
                    MeasurementEvent(
                        index: idx,
                        mode: mode,
                        kind: .heterodyne,
                        values: [qp.0, qp.1]
                    )
                )

            // --- Gaussian channels (non-unitary; apply here, NOT in lowering) ---

            case .loss(let eta, let mode):
                state = try GaussianChannels.applyLoss(state, mode: mode, eta: eta)

            case .thermalLoss(let eta, let nTh, let mode):
                state = try GaussianChannels.applyThermalLoss(state, mode: mode, eta: eta, nTh: nTh)

            // --- Future / placeholders ---

            case .noisePlaceholder:
                throw SimulatorError.unsupportedGate(g)

            // --- Gaussian unitary/affine ops (lower -> symplectic apply) ---

            default:
                let op = try lower(g, modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)
            }
        }

        return SimulationResult(finalState: state, measurements: events)
    }

    /// Backwards-compatible API (no measurements returned)
    public static func run(
        _ circuit: Circuit,
        initial: GaussianState? = nil
    ) throws -> GaussianState {

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let result = try runAndMeasure(circuit, initial: initial, rng: &rng)
        return result.finalState
    }

    // MARK: - Lowering (Gate -> CVGate)
    // Only unitary Gaussian ops are lowered.
    // Measurements and channels MUST be handled in runAndMeasure.

    private static func lower(_ gate: Gate, modes: Int) throws -> CVGate {
        switch gate {

        case .phase(let theta, let mode):
            return CVGate.phaseShift(theta: theta, mode: mode, modes: modes)

        case .squeeze(let r, let mode):
            return CVGate.squeeze(r: r, mode: mode, modes: modes)

        case .beamSplitter(let theta, let a, let b):
            return CVGate.beamSplitter(theta: theta, modeA: a, modeB: b, modes: modes)

        case .displace(let q, let p, let mode):
            let dim = 2 * modes
            var d = Array(repeating: 0.0, count: dim)
            let i = 2 * mode
            d[i] = q
            d[i + 1] = p
            return CVGate(S: LA.eye(dim), d: d)

        // MUST NOT be lowered
        case .measureHomodyne, .measureHeterodyne:
            throw SimulatorError.invalidLowering("Measurement gate must not be lowered")

        case .loss, .thermalLoss:
            throw SimulatorError.invalidLowering("Noise channel must not be lowered")

        case .noisePlaceholder:
            throw SimulatorError.unsupportedGate(gate)
        }
    }
}