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

    // NOTE: intentionally NOT Equatable (contains floating measurement samples).
    public struct SimulationResult: Sendable {
        public let finalState: GaussianState
        public let measurements: [MeasurementEvent]
    }

    // MARK: - Public API

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

        for (idx, gate) in circuit.gates.enumerated() {
            switch gate {

            // ==========================
            // Measurements (sample + condition)
            // ==========================

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

            // ==========================
            // Non-unitary Gaussian channels (apply here, NOT in lowering)
            // ==========================

            case .loss(let eta, let mode):
                state = try GaussianChannels.applyLoss(state, mode: mode, eta: eta)

            case .thermalLoss(let eta, let nTh, let mode):
                state = try GaussianChannels.applyThermalLoss(state, mode: mode, eta: eta, nTh: nTh)

            // ==========================
            // Non-Gaussian injection (IR-level)
            // ==========================
            // For now:
            // - Fock/cat: reject (needs Fock backend)
            // - GKP: optionally approximate as Gaussian additive noise (if you want)
            //
            case .injectNonGaussian(let ng):
                try applyNonGaussianInjection(&state, ng, circuitModes: circuit.modes)

            // ==========================
            // Placeholders
            // ==========================

            case .noisePlaceholder:
                throw SimulatorError.unsupportedGate(gate)

            // ==========================
            // Gaussian unitaries / affine ops (lower -> apply)
            // ==========================

            case .phase, .squeeze, .beamSplitter, .displace:
                let op = try lower(gate, modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)
            }
        }

        return SimulationResult(finalState: state, measurements: events)
    }

    /// Convenience API: ignores measurement record (but still samples internally).
    public static func run(
        _ circuit: Circuit,
        initial: GaussianState? = nil
    ) throws -> GaussianState {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        return try runAndMeasure(circuit, initial: initial, rng: &rng).finalState
    }

    // MARK: - Lowering (Gate -> CVGate)
    // Only unitary Gaussian ops are lowered.
    // Measurements / channels / injections MUST be handled in runAndMeasure.

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

        case .injectNonGaussian:
            throw SimulatorError.invalidLowering("Non-Gaussian injection must be handled at runtime")

        case .noisePlaceholder:
            throw SimulatorError.unsupportedGate(gate)
        }
    }

    // MARK: - Injection handler (runtime only)

    private static func applyNonGaussianInjection(
        _ state: inout GaussianState,
        _ ng: NonGaussianState,
        circuitModes: Int
    ) throws {
        switch ng {

        case .gkp(let delta, let mode):
            // Option: Effective-GKP approximation as additive Gaussian noise.
            // This keeps Gaussian backend usable for “GKP-only” circuits.
            //
            // If you want STRICT behavior instead, replace this whole case with:
            // throw SimulatorError.unsupportedGate(.injectNonGaussian(ng))
            //
            guard (0..<circuitModes).contains(mode) else {
                throw SimulatorError.invalidLowering("GKP injection mode \(mode) out of range")
            }
            let v = delta * delta
            state = try GaussianAdditiveNoise.apply(state, mode: mode, vq: v, vp: v)

        case .fock, .cat:
            // Needs a true non-Gaussian (Fock) backend
            throw SimulatorError.unsupportedGate(.injectNonGaussian(ng))
        }
    }
}