// core-swift/Sources/SchroSIM/backends/backend_capabilities.swift

public protocol BackendCapabilities {
    var supportsGaussian: Bool { get }
    var supportsFock: Bool { get }
    var supportsMeasurement: Bool { get }
    var supportsFeedForward: Bool { get }
}
