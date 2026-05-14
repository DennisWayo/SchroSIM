import CryptoKit
import Foundation
import SchroSIM

let foundryRegistryCurrentSchemaVersion = 1

enum FoundryRegistryStatus: String, Codable {
    case draft
    case approved
    case deprecated
}

struct FoundryRegistrySpec: Codable {
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

    func toFoundrySpec(defaultName: String) -> FoundrySpec {
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

struct FoundryRegistryHistoryEvent: Codable {
    let timestamp: String
    let action: String
    let by: String
    let note: String?
}

struct FoundryRegistryProfile: Codable {
    let profileID: String
    let version: Int
    var status: FoundryRegistryStatus
    let validFrom: String
    let validTo: String?
    var approvers: [String]
    let changeTicket: String?
    var signature: String?
    let spec: FoundryRegistrySpec
    var history: [FoundryRegistryHistoryEvent]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case version
        case status
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case approvers
        case changeTicket = "change_ticket"
        case signature
        case spec
        case history
    }
}

struct FoundryRegistryDocument: Codable {
    let schemaVersion: Int
    var profiles: [FoundryRegistryProfile]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profiles
    }
}

struct ResolvedFoundryProfile {
    let profileID: String
    let version: Int
    let status: FoundryRegistryStatus
    let spec: FoundryRegistrySpec
}

enum FoundryRegistryError: Error, CustomStringConvertible {
    case malformedRegistry(String)
    case unsupportedSchemaVersion(Int)
    case missingProfile(String, Int)
    case nonApprovedProfile(String, Int, FoundryRegistryStatus)
    case unsignedProfile(String, Int)
    case invalidSignature(String, Int)
    case invalidValidityWindow(String, Int, String)
    case expiredProfile(String, Int, String)
    case invalidTransition(from: FoundryRegistryStatus, to: FoundryRegistryStatus)
    case duplicateProfile(String, Int)

    var description: String {
        switch self {
        case .malformedRegistry(let message):
            return "Malformed foundry registry: \(message)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported foundry registry schema_version '\(version)'; expected \(foundryRegistryCurrentSchemaVersion)"
        case .missingProfile(let id, let version):
            return "Foundry profile not found: profile_id='\(id)', version=\(version)"
        case .nonApprovedProfile(let id, let version, let status):
            return "Foundry profile '\(id)' version \(version) is not approved (status=\(status.rawValue))"
        case .unsignedProfile(let id, let version):
            return "Foundry profile '\(id)' version \(version) is missing a signature"
        case .invalidSignature(let id, let version):
            return "Foundry signature verification failed for '\(id)' version \(version)"
        case .invalidValidityWindow(let id, let version, let message):
            return "Foundry profile '\(id)' version \(version) has invalid validity window: \(message)"
        case .expiredProfile(let id, let version, let at):
            return "Foundry profile '\(id)' version \(version) is expired/not-yet-valid at \(at)"
        case .invalidTransition(let from, let to):
            return "Invalid foundry status transition '\(from.rawValue)' -> '\(to.rawValue)'"
        case .duplicateProfile(let id, let version):
            return "Duplicate foundry profile entry: profile_id='\(id)', version=\(version)"
        }
    }
}

func parseISO8601Date(_ value: String) -> Date? {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) {
        return date
    }

    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: value)
}

func currentISO8601Timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

func hmacSHA256Hex(message: Data, key: String) -> String {
    let keyData = Data(key.utf8)
    let symmetricKey = SymmetricKey(data: keyData)
    let signature = HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey)
    return signature.map { String(format: "%02x", $0) }.joined()
}

func foundrySpecJSONObject(_ spec: FoundryRegistrySpec) -> [String: Any] {
    var payload: [String: Any] = [
        "name": spec.name ?? NSNull(),
        "allow_non_gaussian": spec.allowNonGaussian ?? true,
        "allow_measurements": spec.allowMeasurements ?? true,
        "mode_loss_eta": spec.modeLossEta ?? [],
        "inject_mode_loss": spec.injectModeLoss ?? true
    ]
    payload["max_modes"] = spec.maxModes ?? NSNull()
    payload["max_squeezing_r"] = spec.maxSqueezingR ?? NSNull()
    return payload
}

func foundryProfileSigningData(_ profile: FoundryRegistryProfile) throws -> Data {
    let payload: [String: Any] = [
        "profile_id": profile.profileID,
        "version": profile.version,
        "status": profile.status.rawValue,
        "valid_from": profile.validFrom,
        "valid_to": profile.validTo ?? NSNull(),
        "approvers": profile.approvers,
        "change_ticket": profile.changeTicket ?? NSNull(),
        "spec": foundrySpecJSONObject(profile.spec)
    ]
    return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
}

func signFoundryProfile(_ profile: FoundryRegistryProfile, key: String) throws -> String {
    let payload = try foundryProfileSigningData(profile)
    return hmacSHA256Hex(message: payload, key: key)
}

func verifyFoundryProfileSignature(_ profile: FoundryRegistryProfile, key: String) throws -> Bool {
    guard let signature = profile.signature, !signature.isEmpty else {
        return false
    }
    let expected = try signFoundryProfile(profile, key: key)
    return expected == signature.lowercased()
}

func loadFoundryRegistry(path: String) throws -> FoundryRegistryDocument {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let registry = try JSONDecoder().decode(FoundryRegistryDocument.self, from: data)

    guard registry.schemaVersion == foundryRegistryCurrentSchemaVersion else {
        throw FoundryRegistryError.unsupportedSchemaVersion(registry.schemaVersion)
    }

    var seen = Set<String>()
    for profile in registry.profiles {
        let key = "\(profile.profileID)#\(profile.version)"
        if seen.contains(key) {
            throw FoundryRegistryError.duplicateProfile(profile.profileID, profile.version)
        }
        seen.insert(key)
    }

    return registry
}

func writeFoundryRegistry(_ registry: FoundryRegistryDocument, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(registry)

    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic])
}

func resolveFoundryProfileFromRegistry(
    registryPath: String,
    profileID: String,
    version: Int,
    signingKey: String,
    now: Date
) throws -> ResolvedFoundryProfile {
    let registry = try loadFoundryRegistry(path: registryPath)
    guard let profile = registry.profiles.first(where: { $0.profileID == profileID && $0.version == version }) else {
        throw FoundryRegistryError.missingProfile(profileID, version)
    }

    guard profile.status == .approved else {
        throw FoundryRegistryError.nonApprovedProfile(profileID, version, profile.status)
    }

    guard let fromDate = parseISO8601Date(profile.validFrom) else {
        throw FoundryRegistryError.invalidValidityWindow(profileID, version, "valid_from must be ISO-8601")
    }

    if now < fromDate {
        throw FoundryRegistryError.expiredProfile(profileID, version, currentISO8601Timestamp())
    }

    if let validTo = profile.validTo {
        guard let toDate = parseISO8601Date(validTo) else {
            throw FoundryRegistryError.invalidValidityWindow(profileID, version, "valid_to must be ISO-8601")
        }
        if now > toDate {
            throw FoundryRegistryError.expiredProfile(profileID, version, currentISO8601Timestamp())
        }
    }

    guard profile.signature != nil else {
        throw FoundryRegistryError.unsignedProfile(profileID, version)
    }
    guard try verifyFoundryProfileSignature(profile, key: signingKey) else {
        throw FoundryRegistryError.invalidSignature(profileID, version)
    }

    return ResolvedFoundryProfile(
        profileID: profile.profileID,
        version: profile.version,
        status: profile.status,
        spec: profile.spec
    )
}

func findProfileIndex(_ registry: FoundryRegistryDocument, profileID: String, version: Int) -> Int? {
    registry.profiles.firstIndex { $0.profileID == profileID && $0.version == version }
}

func makeHistoryEvent(action: String, by: String, note: String?) -> FoundryRegistryHistoryEvent {
    FoundryRegistryHistoryEvent(
        timestamp: currentISO8601Timestamp(),
        action: action,
        by: by,
        note: note
    )
}

func validateFoundryTransition(from: FoundryRegistryStatus, to: FoundryRegistryStatus) throws {
    switch (from, to) {
    case (.draft, .approved), (.approved, .deprecated):
        return
    default:
        throw FoundryRegistryError.invalidTransition(from: from, to: to)
    }
}

func parseFoundryAdminOptions(_ arguments: [String]) throws -> [String: String] {
    var options: [String: String] = [:]
    var idx = 0

    while idx < arguments.count {
        let token = arguments[idx]
        guard token.hasPrefix("--") else {
            throw CLIInputError.invalidArguments("Unexpected token '\(token)'")
        }

        let key = String(token.dropFirst(2))
        let next = idx + 1
        if next < arguments.count, !arguments[next].hasPrefix("--") {
            options[key] = arguments[next]
            idx += 2
        } else {
            options[key] = "true"
            idx += 1
        }
    }

    return options
}

func parseFoundrySpecFile(path: String) throws -> FoundryRegistrySpec {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(FoundryRegistrySpec.self, from: data)
}

func handleFoundryAdmin(arguments: [String]) -> Int32 {
    guard let subcommand = arguments.first else {
        emitJSON([
            "command": "foundry-admin",
            "status": "error",
            "error": "Missing subcommand",
            "usage": [
                "schrosim-cli foundry-admin add-draft --profile-id <id> --version <n> --spec <file> --approver <name> [--registry <file>] [--valid-from <iso8601>] [--valid-to <iso8601>] [--change-ticket <id>] [--note <text>]",
                "schrosim-cli foundry-admin promote --profile-id <id> --version <n> --to <approved|deprecated> --approver <name> [--registry <file>] [--key <secret>] [--note <text>]"
            ]
        ])
        return 1
    }

    let optionArgs = Array(arguments.dropFirst())
    let options: [String: String]
    do {
        options = try parseFoundryAdminOptions(optionArgs)
    } catch {
        emitJSON([
            "command": "foundry-admin",
            "subcommand": subcommand,
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }

    let registryPath = options["registry"] ?? defaultFoundryRegistryPath

    do {
        switch subcommand {
        case "add-draft":
            guard let profileID = options["profile-id"], !profileID.isEmpty else {
                throw CLIInputError.missingField("Missing required option --profile-id")
            }
            guard let versionText = options["version"], let version = Int(versionText), version > 0 else {
                throw CLIInputError.invalidField("Option --version must be a positive integer")
            }
            guard let specPath = options["spec"], !specPath.isEmpty else {
                throw CLIInputError.missingField("Missing required option --spec")
            }
            guard let approver = options["approver"], !approver.isEmpty else {
                throw CLIInputError.missingField("Missing required option --approver")
            }

            var registry: FoundryRegistryDocument
            if FileManager.default.fileExists(atPath: registryPath) {
                registry = try loadFoundryRegistry(path: registryPath)
            } else {
                registry = FoundryRegistryDocument(schemaVersion: foundryRegistryCurrentSchemaVersion, profiles: [])
            }

            if findProfileIndex(registry, profileID: profileID, version: version) != nil {
                throw FoundryRegistryError.duplicateProfile(profileID, version)
            }

            let spec = try parseFoundrySpecFile(path: specPath)
            let validFrom = options["valid-from"] ?? currentISO8601Timestamp()
            if parseISO8601Date(validFrom) == nil {
                throw CLIInputError.invalidField("Option --valid-from must be ISO-8601")
            }

            let validTo = options["valid-to"]
            if let validTo, parseISO8601Date(validTo) == nil {
                throw CLIInputError.invalidField("Option --valid-to must be ISO-8601")
            }

            let note = options["note"]

            var history: [FoundryRegistryHistoryEvent] = []
            history.append(makeHistoryEvent(action: "created_draft", by: approver, note: note))

            let profile = FoundryRegistryProfile(
                profileID: profileID,
                version: version,
                status: .draft,
                validFrom: validFrom,
                validTo: validTo,
                approvers: [approver],
                changeTicket: options["change-ticket"],
                signature: nil,
                spec: spec,
                history: history
            )

            registry.profiles.append(profile)
            registry.profiles.sort { lhs, rhs in
                if lhs.profileID == rhs.profileID {
                    return lhs.version < rhs.version
                }
                return lhs.profileID < rhs.profileID
            }

            try writeFoundryRegistry(registry, path: registryPath)
            emitJSON([
                "command": "foundry-admin",
                "subcommand": subcommand,
                "status": "success",
                "registry": registryPath,
                "profile_id": profileID,
                "version": version,
                "new_status": "draft"
            ])
            return 0

        case "promote":
            guard let profileID = options["profile-id"], !profileID.isEmpty else {
                throw CLIInputError.missingField("Missing required option --profile-id")
            }
            guard let versionText = options["version"], let version = Int(versionText), version > 0 else {
                throw CLIInputError.invalidField("Option --version must be a positive integer")
            }
            guard let toRaw = options["to"], let targetStatus = FoundryRegistryStatus(rawValue: toRaw) else {
                throw CLIInputError.invalidField("Option --to must be one of: approved, deprecated")
            }
            guard let approver = options["approver"], !approver.isEmpty else {
                throw CLIInputError.missingField("Missing required option --approver")
            }

            var registry = try loadFoundryRegistry(path: registryPath)
            guard let idx = findProfileIndex(registry, profileID: profileID, version: version) else {
                throw FoundryRegistryError.missingProfile(profileID, version)
            }

            try validateFoundryTransition(from: registry.profiles[idx].status, to: targetStatus)
            registry.profiles[idx].status = targetStatus

            if !registry.profiles[idx].approvers.contains(approver) {
                registry.profiles[idx].approvers.append(approver)
            }

            if targetStatus == .approved {
                let signingKey = options["key"]
                    ?? ProcessInfo.processInfo.environment["SCHROSIM_FOUNDRY_HMAC_KEY"]

                guard let signingKey, !signingKey.isEmpty else {
                    throw CLIInputError.missingField(
                        "Missing signing key. Provide --key or SCHROSIM_FOUNDRY_HMAC_KEY"
                    )
                }

                let signature = try signFoundryProfile(registry.profiles[idx], key: signingKey)
                registry.profiles[idx].signature = signature
            }

            let note = options["note"]
            registry.profiles[idx].history.append(
                makeHistoryEvent(action: "promoted_\(targetStatus.rawValue)", by: approver, note: note)
            )

            try writeFoundryRegistry(registry, path: registryPath)
            emitJSON([
                "command": "foundry-admin",
                "subcommand": subcommand,
                "status": "success",
                "registry": registryPath,
                "profile_id": profileID,
                "version": version,
                "new_status": targetStatus.rawValue,
                "signature_present": registry.profiles[idx].signature != nil
            ])
            return 0

        default:
            emitJSON([
                "command": "foundry-admin",
                "subcommand": subcommand,
                "status": "error",
                "error": "Unknown subcommand '\(subcommand)'"
            ])
            return 1
        }
    } catch {
        emitJSON([
            "command": "foundry-admin",
            "subcommand": subcommand,
            "status": "error",
            "error": String(describing: error)
        ])
        return 1
    }
}
