import Foundation

let traceRBACCurrentSchemaVersion = 1
let traceArtifactCurrentSchemaVersion = 1
let defaultTraceRBACPolicyPath = "config/trace_rbac_policy.json"

enum TraceRBACAction: String {
    case view
    case export
    case share
}

enum TraceStreamFormat: String {
    case ndjson
    case sse
}

struct TraceFrameRecord: Sendable {
    let frameIndex: Int
    let gateIndex: Int?
    let gateType: String
    let meanPhotonNumber: Double
    let measurementCount: Int
    let frameLatencyMs: Double
}

struct TraceFrameCollectionResult {
    let frames: [TraceFrameRecord]
    let originalCount: Int
    let droppedCount: Int
    let downsampleApplied: Bool
    let ringBufferApplied: Bool
    let maxFrameLatencyMs: Double
}

private struct TraceRBACDocument: Codable {
    let schemaVersion: Int
    let roles: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case roles
    }
}

enum TraceSupportError: Error, CustomStringConvertible {
    case malformedRBACPolicy(String)
    case unsupportedRBACSchemaVersion(Int)
    case unknownRBACRole(String)
    case forbiddenRBACAction(role: String, action: String)
    case invalidTraceOption(String)
    case invalidTraceStreamFormat(String)
    case malformedTraceArtifact(String)
    case traceReplayChecksumMismatch(expected: String, actual: String)
    case missingTraceSigningKey
    case traceSignatureMismatch

    var description: String {
        switch self {
        case .malformedRBACPolicy(let message):
            return "Malformed trace RBAC policy: \(message)"
        case .unsupportedRBACSchemaVersion(let version):
            return "Unsupported trace RBAC schema_version '\(version)'; expected \(traceRBACCurrentSchemaVersion)"
        case .unknownRBACRole(let role):
            return "Unknown trace role '\(role)'"
        case .forbiddenRBACAction(let role, let action):
            return "RBAC denied action '\(action)' for role '\(role)'"
        case .invalidTraceOption(let message):
            return "Invalid trace option: \(message)"
        case .invalidTraceStreamFormat(let format):
            return "Unsupported trace stream format '\(format)'; expected 'ndjson' or 'sse'"
        case .malformedTraceArtifact(let message):
            return "Malformed trace artifact: \(message)"
        case .traceReplayChecksumMismatch(let expected, let actual):
            return "Trace replay checksum mismatch: expected \(expected), got \(actual)"
        case .missingTraceSigningKey:
            return "Missing trace signing key. Provide --trace-key or SCHROSIM_TRACE_HMAC_KEY"
        case .traceSignatureMismatch:
            return "Trace artifact signature verification failed"
        }
    }
}

typealias TraceEnterpriseError = TraceSupportError

private struct TraceRingBuffer<Element> {
    private var storage: [Element?]
    private var head = 0
    private var count = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        let capacity = storage.count
        if count < capacity {
            storage[(head + count) % capacity] = element
            count += 1
            return
        }

        storage[head] = element
        head = (head + 1) % capacity
    }

    func toArray() -> [Element] {
        let capacity = storage.count
        var out: [Element] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            if let value = storage[(head + i) % capacity] {
                out.append(value)
            }
        }
        return out
    }
}

struct TraceFrameCollector {
    let maxFrames: Int?
    let ringBufferCapacity: Int?
    private var frames: [TraceFrameRecord]
    private var ringBuffer: TraceRingBuffer<TraceFrameRecord>?
    private(set) var originalCount: Int
    private(set) var maxFrameLatencyMs: Double

    init(maxFrames: Int?, ringBufferCapacity: Int?) {
        self.maxFrames = maxFrames
        self.ringBufferCapacity = ringBufferCapacity
        self.frames = []
        self.ringBuffer = nil
        self.originalCount = 0
        self.maxFrameLatencyMs = 0.0

        if let ringBufferCapacity, ringBufferCapacity > 0 {
            self.ringBuffer = TraceRingBuffer<TraceFrameRecord>(capacity: ringBufferCapacity)
        }
    }

    mutating func append(_ frame: TraceFrameRecord) {
        originalCount += 1
        maxFrameLatencyMs = max(maxFrameLatencyMs, frame.frameLatencyMs)
        if var ringBuffer {
            ringBuffer.append(frame)
            self.ringBuffer = ringBuffer
        } else {
            frames.append(frame)
        }
    }

    mutating func finish() -> TraceFrameCollectionResult {
        let usedRingBuffer = ringBuffer != nil
        var outputFrames: [TraceFrameRecord]
        if let ringBuffer {
            outputFrames = ringBuffer.toArray()
        } else {
            outputFrames = frames
        }

        var downsampleApplied = false
        if let maxFrames, maxFrames > 0, outputFrames.count > maxFrames {
            outputFrames = adaptiveDownsample(outputFrames, maxFrames: maxFrames)
            downsampleApplied = true
        }

        let droppedCount = max(0, originalCount - outputFrames.count)
        return TraceFrameCollectionResult(
            frames: outputFrames,
            originalCount: originalCount,
            droppedCount: droppedCount,
            downsampleApplied: downsampleApplied,
            ringBufferApplied: usedRingBuffer,
            maxFrameLatencyMs: maxFrameLatencyMs
        )
    }
}

func traceFrameJSONObject(_ frame: TraceFrameRecord) -> [String: Any] {
    [
        "frame_index": frame.frameIndex,
        "gate_index": frame.gateIndex ?? NSNull(),
        "gate_type": frame.gateType,
        "mean_photon_number": frame.meanPhotonNumber,
        "measurement_count": frame.measurementCount,
        "frame_latency_ms": frame.frameLatencyMs
    ]
}

func parseTraceStreamFormat(_ rawValue: String?) throws -> TraceStreamFormat {
    let resolved = (rawValue ?? TraceStreamFormat.ndjson.rawValue).lowercased()
    guard let format = TraceStreamFormat(rawValue: resolved) else {
        throw TraceSupportError.invalidTraceStreamFormat(resolved)
    }
    return format
}

private func adaptiveDownsample(_ frames: [TraceFrameRecord], maxFrames: Int) -> [TraceFrameRecord] {
    guard maxFrames > 0 else { return [] }
    guard frames.count > maxFrames else { return frames }
    guard maxFrames > 1 else { return [frames.last ?? frames[0]] }

    let step = Double(frames.count - 1) / Double(maxFrames - 1)
    var indices = Set<Int>()
    for i in 0..<maxFrames {
        let idx = Int((Double(i) * step).rounded())
        indices.insert(max(0, min(frames.count - 1, idx)))
    }

    if indices.count < maxFrames {
        for idx in 0..<frames.count {
            if !indices.contains(idx) {
                indices.insert(idx)
                if indices.count == maxFrames {
                    break
                }
            }
        }
    }

    var ordered = Array(indices).sorted()
    if ordered.count > maxFrames {
        ordered = Array(ordered.prefix(maxFrames))
        ordered.sort()
    }
    return ordered.map { frames[$0] }
}

private func traceRBACDefaults() -> [String: Set<TraceRBACAction>] {
    [
        "viewer": [.view],
        "editor": [.view, .export],
        "approver": [.view, .export, .share],
        "admin": [.view, .export, .share]
    ]
}

private func loadTraceRBACRoles(path: String?) throws -> [String: Set<TraceRBACAction>] {
    let fallback = traceRBACDefaults()
    let resolvedPath: String?
    if let path {
        resolvedPath = path
    } else if FileManager.default.fileExists(atPath: defaultTraceRBACPolicyPath) {
        resolvedPath = defaultTraceRBACPolicyPath
    } else {
        resolvedPath = nil
    }

    guard let resolvedPath else {
        return fallback
    }

    guard FileManager.default.fileExists(atPath: resolvedPath) else {
        throw TraceSupportError.malformedRBACPolicy("policy file does not exist: \(resolvedPath)")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
    let doc = try JSONDecoder().decode(TraceRBACDocument.self, from: data)
    guard doc.schemaVersion == traceRBACCurrentSchemaVersion else {
        throw TraceSupportError.unsupportedRBACSchemaVersion(doc.schemaVersion)
    }

    var roles: [String: Set<TraceRBACAction>] = [:]
    for (role, actionsRaw) in doc.roles {
        var actions = Set<TraceRBACAction>()
        for raw in actionsRaw {
            guard let action = TraceRBACAction(rawValue: raw) else {
                throw TraceSupportError.malformedRBACPolicy("unknown action '\(raw)' for role '\(role)'")
            }
            actions.insert(action)
        }
        roles[role] = actions
    }

    for (role, actions) in fallback where roles[role] == nil {
        roles[role] = actions
    }
    return roles
}

func requireTraceRBACAction(role: String, action: TraceRBACAction, policyPath: String?) throws {
    let roles = try loadTraceRBACRoles(path: policyPath)
    guard let allowed = roles[role] else {
        throw TraceSupportError.unknownRBACRole(role)
    }
    guard allowed.contains(action) else {
        throw TraceSupportError.forbiddenRBACAction(role: role, action: action.rawValue)
    }
}

func traceReplayChecksum(
    schemaVersion: Int,
    backend: String,
    compiler: String,
    contractionType: String,
    foundryProfileHash: String,
    seed: UInt64?,
    computeBackendRequested: String? = nil,
    computeBackendCandidate: String? = nil,
    computeBackendUsed: String? = nil,
    computeBackendFallbackReason: String? = nil,
    frames: [TraceFrameRecord]
) -> String {
    func q(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.12f", value)
    }

    let normalizedFrames = frames.map { frame in
        [
            "frame_index": frame.frameIndex,
            "gate_index": frame.gateIndex ?? NSNull(),
            "gate_type": frame.gateType,
            "mean_photon_number_q": q(frame.meanPhotonNumber),
            "measurement_count": frame.measurementCount,
            "frame_latency_ms_q": q(frame.frameLatencyMs)
        ] as [String: Any]
    }

    var payload: [String: Any] = [
        "schema_version": schemaVersion,
        "backend": backend,
        "compiler": compiler,
        "contraction_type": contractionType,
        "foundry_profile_hash": foundryProfileHash,
        "seed": seed.map(String.init) ?? NSNull(),
        "frames": normalizedFrames
    ]

    if let computeBackendRequested {
        payload["compute_backend_requested"] = computeBackendRequested
    }
    if let computeBackendCandidate {
        payload["compute_backend_candidate"] = computeBackendCandidate
    }
    if let computeBackendUsed {
        payload["compute_backend_used"] = computeBackendUsed
    }
    if let computeBackendFallbackReason {
        payload["compute_backend_fallback_reason"] = computeBackendFallbackReason
    }

    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
        return "unavailable"
    }
    return deterministicSHA256Hex(of: data)
}

private func compactJSONData(_ payload: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
}

func writeJSONObject(_ payload: [String: Any], to path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic])
}

func makeTraceArtifactEnvelope(payload: [String: Any], signingKey: String?) throws -> [String: Any] {
    var envelope: [String: Any] = [
        "schema_version": traceArtifactCurrentSchemaVersion,
        "artifact_type": "schrosim.trace.artifact",
        "generated_at": currentISO8601Timestamp(),
        "payload": payload
    ]

    var signature: Any = NSNull()
    if let signingKey, !signingKey.isEmpty {
        let signable = try compactJSONData(envelope)
        signature = hmacSHA256Hex(message: signable, key: signingKey)
    }
    envelope["signature"] = signature
    return envelope
}

func emitTraceStreamEvent(format: TraceStreamFormat, event: String, payload: [String: Any]) throws {
    switch format {
    case .ndjson:
        var line = payload
        line["event"] = event
        let data = try compactJSONData(line)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
        fflush(stdout)
    case .sse:
        let data = try compactJSONData(payload)
        let json = String(decoding: data, as: UTF8.self)
        FileHandle.standardOutput.write(Data("event: \(event)\n".utf8))
        FileHandle.standardOutput.write(Data("data: \(json)\n\n".utf8))
        fflush(stdout)
    }
}

func decodeJSONObject(path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TraceSupportError.malformedTraceArtifact("expected top-level JSON object")
    }
    return object
}

private func parseUInt64String(_ value: Any?) -> UInt64? {
    if let value = value as? UInt64 { return value }
    if let value = value as? Int, value >= 0 { return UInt64(value) }
    if let value = value as? String { return UInt64(value) }
    return nil
}

private func parseOptionalString(_ value: Any?) -> String? {
    guard !(value is NSNull) else { return nil }
    return value as? String
}

private func parseInt(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

private func parseDouble(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

func parseTraceFrames(from payload: [String: Any]) throws -> [TraceFrameRecord] {
    guard let rawFrames = payload["frames"] as? [Any] else {
        throw TraceSupportError.malformedTraceArtifact("payload.frames must be an array")
    }

    var frames: [TraceFrameRecord] = []
    frames.reserveCapacity(rawFrames.count)
    for raw in rawFrames {
        guard let dict = raw as? [String: Any] else {
            throw TraceSupportError.malformedTraceArtifact("frame entry is not an object")
        }

        guard let frameIndex = parseInt(dict["frame_index"]) else {
            throw TraceSupportError.malformedTraceArtifact("frame_index missing or invalid")
        }
        let gateIndex: Int?
        if dict["gate_index"] is NSNull {
            gateIndex = nil
        } else {
            gateIndex = parseInt(dict["gate_index"])
        }
        guard let gateType = dict["gate_type"] as? String else {
            throw TraceSupportError.malformedTraceArtifact("gate_type missing or invalid")
        }
        guard let meanPhoton = parseDouble(dict["mean_photon_number"]) else {
            throw TraceSupportError.malformedTraceArtifact("mean_photon_number missing or invalid")
        }
        guard let measurementCount = parseInt(dict["measurement_count"]) else {
            throw TraceSupportError.malformedTraceArtifact("measurement_count missing or invalid")
        }
        let frameLatency = parseDouble(dict["frame_latency_ms"]) ?? 0.0

        frames.append(
            TraceFrameRecord(
                frameIndex: frameIndex,
                gateIndex: gateIndex,
                gateType: gateType,
                meanPhotonNumber: meanPhoton,
                measurementCount: measurementCount,
                frameLatencyMs: frameLatency
            )
        )
    }

    return frames
}

func traceReplayChecksumFromPayload(_ payload: [String: Any]) throws -> String {
    guard let schemaVersion = parseInt(payload["schema_version"]) else {
        throw TraceSupportError.malformedTraceArtifact("payload.schema_version missing or invalid")
    }
    guard let backend = payload["backend"] as? String else {
        throw TraceSupportError.malformedTraceArtifact("payload.backend missing or invalid")
    }
    guard let compiler = payload["compiler"] as? String else {
        throw TraceSupportError.malformedTraceArtifact("payload.compiler missing or invalid")
    }
    guard let contractionType = payload["contraction_type"] as? String else {
        throw TraceSupportError.malformedTraceArtifact("payload.contraction_type missing or invalid")
    }
    guard let provenance = payload["provenance"] as? [String: Any] else {
        throw TraceSupportError.malformedTraceArtifact("payload.provenance missing or invalid")
    }
    guard let foundryProfileHash = provenance["foundry_profile_hash"] as? String else {
        throw TraceSupportError.malformedTraceArtifact("payload.provenance.foundry_profile_hash missing or invalid")
    }
    let frames = try parseTraceFrames(from: payload)
    let seed = parseUInt64String(provenance["seed"])
    let computeBackendRequested = parseOptionalString(payload["compute_backend_requested"])
        ?? parseOptionalString(provenance["compute_backend_requested"])
    let computeBackendCandidate = parseOptionalString(payload["compute_backend_candidate"])
        ?? parseOptionalString(provenance["compute_backend_candidate"])
    let computeBackendUsed = parseOptionalString(payload["compute_backend_used"])
        ?? parseOptionalString(provenance["compute_backend_used"])
    let computeBackendFallbackReason = parseOptionalString(payload["compute_backend_fallback_reason"])
        ?? parseOptionalString(provenance["compute_backend_fallback_reason"])

    return traceReplayChecksum(
        schemaVersion: schemaVersion,
        backend: backend,
        compiler: compiler,
        contractionType: contractionType,
        foundryProfileHash: foundryProfileHash,
        seed: seed,
        computeBackendRequested: computeBackendRequested,
        computeBackendCandidate: computeBackendCandidate,
        computeBackendUsed: computeBackendUsed,
        computeBackendFallbackReason: computeBackendFallbackReason,
        frames: frames
    )
}

func verifyTraceArtifactEnvelope(_ envelope: [String: Any], key: String?) throws -> (checksum: String, signatureVerified: Bool) {
    guard let payload = envelope["payload"] as? [String: Any] else {
        throw TraceSupportError.malformedTraceArtifact("envelope.payload missing or invalid")
    }

    guard let expectedChecksum = (payload["replay_checksum"] as? String) ?? (envelope["replay_checksum"] as? String) else {
        throw TraceSupportError.malformedTraceArtifact("replay_checksum missing")
    }
    let actualChecksum = try traceReplayChecksumFromPayload(payload)
    guard expectedChecksum == actualChecksum else {
        throw TraceSupportError.traceReplayChecksumMismatch(expected: expectedChecksum, actual: actualChecksum)
    }

    let signature = envelope["signature"]
    guard !(signature is NSNull) else {
        return (checksum: actualChecksum, signatureVerified: false)
    }
    guard let signatureText = signature as? String else {
        throw TraceSupportError.malformedTraceArtifact("signature is malformed")
    }
    guard let key, !key.isEmpty else {
        throw TraceSupportError.missingTraceSigningKey
    }

    var signableEnvelope = envelope
    signableEnvelope.removeValue(forKey: "signature")
    let signable = try compactJSONData(signableEnvelope)
    let expectedSignature = hmacSHA256Hex(message: signable, key: key)
    guard expectedSignature.lowercased() == signatureText.lowercased() else {
        throw TraceSupportError.traceSignatureMismatch
    }

    return (checksum: actualChecksum, signatureVerified: true)
}
