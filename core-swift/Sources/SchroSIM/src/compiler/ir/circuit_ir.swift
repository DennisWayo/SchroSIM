import Foundation

public final class Circuit: @unchecked Sendable {

    public let modes: Int
    public private(set) var gates: [Gate]

    // MARK: - Init

    public init(modes: Int, gates: [Gate] = []) throws {
        guard modes > 0 else {
            throw IRValidationError.invalidModesCount(modes)
        }
        self.modes = modes
        self.gates = []
        for g in gates {
            try append(g)
        }
    }

    // MARK: - DSL

    @discardableResult
    public func injectNonGaussian(_ state: NonGaussianState) -> Self {
        try? append(.injectNonGaussian(state))
        return self
    }

    public func phase(theta: Double, on mode: Int) {
        try? append(.phase(theta: theta, mode: mode))
    }

    public func squeeze(r: Double, on mode: Int) {
        try? append(.squeeze(r: r, mode: mode))
    }

    public func beamSplitter(theta: Double, _ a: Int, _ b: Int) {
        try? append(.beamSplitter(theta: theta, modeA: a, modeB: b))
    }

    public func displace(q: Double, p: Double, on mode: Int) {
        try? append(.displace(q: q, p: p, mode: mode))
    }

    public func loss(eta: Double, on mode: Int) {
        try? append(.loss(eta: eta, mode: mode))
    }

    public func thermalLoss(eta: Double, nTh: Double, on mode: Int) {
        try? append(.thermalLoss(eta: eta, nTh: nTh, mode: mode))
    }

    public func measureHomodyne(mode: Int, theta: Double) {
        try? append(.measureHomodyne(mode: mode, theta: theta))
    }

    public func measureHeterodyne(mode: Int) {
        try? append(.measureHeterodyne(mode: mode))
    }

    // MARK: - Append

    public func append(_ gate: Gate) throws {
        try validate(gate)
        gates.append(gate)
    }

    // MARK: - Validation (ONLY place validation exists)

    private func validate(_ gate: Gate) throws {

        func checkMode(_ m: Int) throws {
            guard m >= 0 && m < modes else {
                throw IRValidationError.invalidMode(m)
            }
        }

        func checkEta(_ eta: Double) throws {
            guard eta.isFinite, eta >= 0.0, eta <= 1.0 else {
                throw IRValidationError.invalidParameter(
                    "Loss eta must be in [0,1], got \(eta)"
                )
            }
        }

        func checkNTh(_ nTh: Double) throws {
            guard nTh.isFinite, nTh >= 0.0 else {
                throw IRValidationError.invalidParameter(
                    "Thermal nTh must be >= 0, got \(nTh)"
                )
            }
        }

        switch gate {

        case .phase(_, let m),
             .squeeze(_, let m),
             .displace(_, _, let m),
             .measureHomodyne(let m, _),
             .measureHeterodyne(let m):
            try checkMode(m)

        case .loss(let eta, let m):
            try checkMode(m)
            try checkEta(eta)

        case .beamSplitter(_, let a, let b):
            try checkMode(a)
            try checkMode(b)
            guard a != b else {
                throw IRValidationError.invalidPair(a, b)
            }

        case .thermalLoss(let eta, let nTh, let m):
            try checkMode(m)
            try checkEta(eta)
            try checkNTh(nTh)

        case .classicalControl(let id, let condition, let inner):
            guard id >= 0 else {
                throw IRValidationError.invalidParameter("Invalid measurement ID")
            }
            if let condition {
                guard condition.valueIndex >= 0 else {
                    throw IRValidationError.invalidParameter("Classical control valueIndex must be >= 0")
                }
                guard condition.threshold.isFinite else {
                    throw IRValidationError.invalidParameter("Classical control threshold must be finite")
                }
            }
            try validate(inner)

        case .feedbackDisplace(
            let on,
            let valueIndex,
            let gainQ,
            let gainP,
            let biasQ,
            let biasP,
            let mode
        ):
            guard on >= 0 else {
                throw IRValidationError.invalidParameter("feedbackDisplace measurement ID must be >= 0")
            }
            guard valueIndex >= 0 else {
                throw IRValidationError.invalidParameter("feedbackDisplace valueIndex must be >= 0")
            }
            guard gainQ.isFinite, gainP.isFinite, biasQ.isFinite, biasP.isFinite else {
                throw IRValidationError.invalidParameter(
                    "feedbackDisplace gainQ/gainP/biasQ/biasP must be finite"
                )
            }
            try checkMode(mode)

        case .gkpDecodeDisplace(
            let on,
            let valueIndex,
            let latticeSpacing,
            _,
            let gainQ,
            let gainP,
            let biasQ,
            let biasP,
            let mode
        ):
            guard on >= 0 else {
                throw IRValidationError.invalidParameter("gkpDecodeDisplace measurement ID must be >= 0")
            }
            guard valueIndex >= 0 else {
                throw IRValidationError.invalidParameter("gkpDecodeDisplace valueIndex must be >= 0")
            }
            guard latticeSpacing.isFinite, latticeSpacing > 0 else {
                throw IRValidationError.invalidParameter("gkpDecodeDisplace latticeSpacing must be > 0 and finite")
            }
            guard gainQ.isFinite, gainP.isFinite, biasQ.isFinite, biasP.isFinite else {
                throw IRValidationError.invalidParameter(
                    "gkpDecodeDisplace gainQ/gainP/biasQ/biasP must be finite"
                )
            }
            try checkMode(mode)

        case .injectNonGaussian(let ng):
            switch ng {
            case .fock(_, let mode),
                 .cat(_, let mode),
                 .gkp(_, let mode):
                try checkMode(mode)
            }

        case .noisePlaceholder:
            break
        }
    }
}
