import Foundation

public final class Circuit: @unchecked Sendable {

    public let modes: Int
    public private(set) var gates: [Gate]

    public init(modes: Int, gates: [Gate] = []) throws {
        guard modes > 0 else {
            throw IRValidationError.invalidModesCount(modes)
        }
        self.modes = modes
        self.gates = []
        for g in gates { try append(g) }
    }

    // MARK: - Append / DSL


    @discardableResult
    public func injectNonGaussian(_ state: NonGaussianState) -> Self {
        try? append(.injectNonGaussian(state))
        return self
    }
    public func append(_ gate: Gate) throws {
        try validate(gate)
        gates.append(gate)
    }

    public func phase(theta: Double, on mode: Int) {
        try? append(.phase(theta: theta, mode: mode))
    }

    public func squeeze(r: Double, on mode: Int) {
        try? append(.squeeze(r: r, mode: mode))
    }

    public func beamSplitter(theta: Double, _ modeA: Int, _ modeB: Int) {
        try? append(.beamSplitter(theta: theta, modeA: modeA, modeB: modeB))
    }

    public func displace(q: Double, p: Double, on mode: Int) {
        try? append(.displace(q: q, p: p, mode: mode))
    }

    // --- Channels / noise (Gaussian) ---

    public func loss(eta: Double, on mode: Int) {
        try? append(.loss(eta: eta, mode: mode))
    }

    // --- Measurements ---

    public func measureHomodyne(mode: Int, theta: Double) {
        try? append(.measureHomodyne(mode: mode, theta: theta))
    }

    public func measureHeterodyne(mode: Int) {
        try? append(.measureHeterodyne(mode: mode))
    }

    public func thermalLoss(eta: Double, nTh: Double, on mode: Int) {
        try? append(.thermalLoss(eta: eta, nTh: nTh, mode: mode))
    }

    // MARK: - Validation

    private func validate(_ gate: Gate) throws {

        func checkMode(_ m: Int) throws {
            guard m >= 0 && m < modes else {
                throw IRValidationError.invalidMode(m)
            }
        }

        func checkEta(_ eta: Double) throws {
            guard eta.isFinite, eta >= 0.0, eta <= 1.0 else {
                throw IRValidationError.invalidParameter("Loss eta must be in [0,1], got \(eta)")
            }
        }

        func checkNTh(_ nTh: Double) throws {
            guard nTh.isFinite, nTh >= 0.0 else {
                throw IRValidationError.invalidParameter("Thermal nTh must be >= 0, got \(nTh)")
            }
        }

        switch gate {
        case .injectNonGaussian:
            // Non-Gaussian injection is validated at runtime by backend
            break

        case .phase(_, let mode):
            try checkMode(mode)

        case .squeeze(_, let mode):
            try checkMode(mode)

        case .displace(_, _, let mode):
            try checkMode(mode)

        case .beamSplitter(_, let a, let b):
            try checkMode(a)
            try checkMode(b)
            guard a != b else { throw IRValidationError.invalidPair(a, b) }

        case .loss(let eta, let mode):
            try checkMode(mode)
            try checkEta(eta)

        case .measureHomodyne(let mode, _):
            try checkMode(mode)

        case .measureHeterodyne(let mode):
            try checkMode(mode)

        case .noisePlaceholder:
            break

        case .thermalLoss(let eta, let nTh, let mode):
            try checkMode(mode)
            try checkEta(eta)
            try checkNTh(nTh)
        }
    }
}