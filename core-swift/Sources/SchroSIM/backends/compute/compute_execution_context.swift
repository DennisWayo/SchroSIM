import Foundation

public enum ComputeExecutionContext {
    private static let lock = NSLock()
    private static var backend: ComputeBackend = .cpu

    public static var currentBackend: ComputeBackend {
        lock.lock()
        defer { lock.unlock() }
        return backend
    }

    public static func setBackend(_ value: ComputeBackend) {
        lock.lock()
        backend = value
        lock.unlock()
    }

    @discardableResult
    public static func withBackend<T>(
        _ value: ComputeBackend,
        _ body: () throws -> T
    ) rethrows -> T {
        lock.lock()
        let previous = backend
        backend = value
        lock.unlock()

        defer {
            lock.lock()
            backend = previous
            lock.unlock()
        }
        return try body()
    }
}
