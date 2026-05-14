import Foundation

public enum SimulatorError: Error, CustomStringConvertible {
    case unsupportedGate(String)
    case invalidLowering(String)

    public var description: String {
        switch self {
        case .unsupportedGate(let msg): return msg
        case .invalidLowering(let msg): return msg
        }
    }
}

public enum Simulator {

    // NOTE: intentionally NOT Equatable (contains floating measurement samples).
    public struct SimulationResult: Sendable {
        public let finalState: GaussianState
        public let measurements: [MeasurementEvent]
    }

    public struct SimulationTraceFrame: Sendable {
        public let gateIndex: Int
        public let gate: Gate
        public let meanPhotonNumber: Double
        public let measurementCount: Int
        public let frameLatencyMs: Double
    }

    public struct SimulationTraceResult: Sendable {
        public let finalState: GaussianState
        public let measurements: [MeasurementEvent]
        public let frames: [SimulationTraceFrame]
    }

    // MARK: - Public API

    public static func runAndMeasure(
        _ circuit: Circuit,
        initial: GaussianState? = nil,
        rng: inout any RandomNumberGenerator
    ) throws -> SimulationResult {
        try runAndMeasureStreaming(circuit, initial: initial, rng: &rng) { _ in }
    }

    public static func runAndMeasureTrace(
        _ circuit: Circuit,
        initial: GaussianState? = nil,
        rng: inout any RandomNumberGenerator
    ) throws -> SimulationTraceResult {
        var frames: [SimulationTraceFrame] = []
        let result = try runAndMeasureStreaming(circuit, initial: initial, rng: &rng) { frame in
            frames.append(frame)
        }
        return SimulationTraceResult(finalState: result.finalState, measurements: result.measurements, frames: frames)
    }

    public static func runAndMeasureStreaming(
        _ circuit: Circuit,
        initial: GaussianState? = nil,
        rng: inout any RandomNumberGenerator,
        onFrame: (SimulationTraceFrame) -> Void
    ) throws -> SimulationResult {

        var state = initial ?? GaussianState.vacuum(modes: circuit.modes)

        guard state.modes == circuit.modes else {
            throw SimulatorError.invalidLowering(
                "Initial state modes \(state.modes) != circuit modes \(circuit.modes)"
            )
        }

        var events: [MeasurementEvent] = []

        for (idx, gate) in circuit.gates.enumerated() {
            let frameStart = CFAbsoluteTimeGetCurrent()
            switch gate {

            case .classicalControl(let id, let condition, let inner):
                guard id < events.count else {
                    throw SimulatorError.invalidLowering(
                        "Classical control refers to non-existent measurement \(id)"
                    )
                }

                if let condition {
                    let measurement = events[id]
                    guard condition.valueIndex < measurement.values.count else {
                        throw SimulatorError.invalidLowering(
                            "Classical control measurement \(id) does not have value index \(condition.valueIndex)"
                        )
                    }

                    let value = measurement.values[condition.valueIndex]
                    if !condition.comparator.evaluate(value: value, threshold: condition.threshold) {
                        break
                    }
                }

                let op = try lower(inner, modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)

            case .feedbackDisplace(
                let on,
                let valueIndex,
                let gainQ,
                let gainP,
                let biasQ,
                let biasP,
                let mode
            ):
                guard on < events.count else {
                    throw SimulatorError.invalidLowering(
                        "feedbackDisplace refers to non-existent measurement \(on)"
                    )
                }
                let measurement = events[on]
                guard valueIndex < measurement.values.count else {
                    throw SimulatorError.invalidLowering(
                        "feedbackDisplace measurement \(on) does not have value index \(valueIndex)"
                    )
                }
                let value = measurement.values[valueIndex]
                let q = gainQ * value + biasQ
                let p = gainP * value + biasP
                let op = try lower(.displace(q: q, p: p, mode: mode), modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)

            case .gkpDecodeDisplace(
                let on,
                let valueIndex,
                let latticeSpacing,
                let targetLatticeIndex,
                let gainQ,
                let gainP,
                let biasQ,
                let biasP,
                let mode
            ):
                guard on < events.count else {
                    throw SimulatorError.invalidLowering(
                        "gkpDecodeDisplace refers to non-existent measurement \(on)"
                    )
                }
                let measurement = events[on]
                guard valueIndex < measurement.values.count else {
                    throw SimulatorError.invalidLowering(
                        "gkpDecodeDisplace measurement \(on) does not have value index \(valueIndex)"
                    )
                }
                let value = measurement.values[valueIndex]
                let decoded = GKPNearestLatticeDecoder.decode(
                    syndromeValue: value,
                    latticeSpacing: latticeSpacing,
                    targetLatticeIndex: targetLatticeIndex
                )
                let q = gainQ * decoded.correction + biasQ
                let p = gainP * decoded.correction + biasP
                let op = try lower(.displace(q: q, p: p, mode: mode), modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)

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
                throw SimulatorError.unsupportedGate("Unsupported gate: \(gate)")

            // ==========================
            // Gaussian unitaries / affine ops (lower -> apply)
            // ==========================

            case .phase, .squeeze, .beamSplitter, .displace:
                let op = try lower(gate, modes: circuit.modes)
                state = SymplecticEvolution.apply(op, to: state)
            }

            onFrame(
                SimulationTraceFrame(
                    gateIndex: idx,
                    gate: gate,
                    meanPhotonNumber: meanPhotonNumber(state),
                    measurementCount: events.count,
                    frameLatencyMs: max(0.0, (CFAbsoluteTimeGetCurrent() - frameStart) * 1000.0)
                )
            )
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
        case .classicalControl:
            throw SimulatorError.invalidLowering(
                "Classical control must be handled at runtime"
            )
        case .feedbackDisplace:
            throw SimulatorError.invalidLowering(
                "feedbackDisplace must be handled at runtime"
            )
        case .gkpDecodeDisplace:
            throw SimulatorError.invalidLowering(
                "gkpDecodeDisplace must be handled at runtime"
            )

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
            throw SimulatorError.unsupportedGate("Unsupported gate: \(gate)")
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
            throw SimulatorError.unsupportedGate(
                "Non-Gaussian state \(ng) requires a Fock backend"
            )
        }
    }
}

private extension Simulator {
    static func meanPhotonNumber(_ state: GaussianState) -> Double {
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
}

extension Simulator: BackendCapabilities {
    public var supportsGaussian: Bool { true }
    public var supportsFock: Bool { false }
    public var supportsMeasurement: Bool { true }
    public var supportsFeedForward: Bool { false }
}
