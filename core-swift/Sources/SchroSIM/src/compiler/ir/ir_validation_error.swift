import Foundation

public enum IRValidationError: Error, CustomStringConvertible {
    case invalidMode(Int)
    case invalidPair(Int, Int)
    case invalidModesCount(Int)
    case invalidParameter(String)

    public var description: String {
        switch self {
        case .invalidMode(let m):
            return "Invalid mode index: \(m)"
        case .invalidPair(let a, let b):
            return "Invalid mode pair: (\(a), \(b))"
        case .invalidModesCount(let n):
            return "Invalid modes count: \(n)"
        case .invalidParameter(let msg):
            return "Invalid parameter: \(msg)"
        }
    }
}