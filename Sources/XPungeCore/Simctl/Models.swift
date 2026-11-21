import Foundation

/// One entry from `simctl runtime list -j`.
public struct Runtime: Decodable, Sendable, Equatable {
    public let identifier: String
    public let version: String
    public let build: String
    public let sizeBytes: Int64
    public let lastUsedAt: Date?
    public let deletable: Bool
    public let kind: String
    public let state: String
    public let runtimeIdentifier: String?
    public let path: String?
    /// Not in simctl's JSON; filled in from the disk image. See `SimctlQueries.runtimes()`.
    public var installedAt: Date?

    /// The most recent sign of life: last use, or install if that's later.
    /// Xcode 26 and later leave `lastUsedAt` empty for most runtimes, so install date stops
    /// a runtime downloaded today from counting as unused for years.
    public var lastActivity: Date? {
        [lastUsedAt, installedAt].compactMap { $0 }.max()
    }

    /// "iOS 17.0" style name derived from the runtime identifier, or the version alone.
    public var displayName: String {
        guard let runtimeIdentifier,
              let platform = runtimeIdentifier.split(separator: ".").last?.split(separator: "-").first
        else { return version }
        return "\(platform) \(version)"
    }

    static func decodeList(_ data: Data) throws -> [Runtime] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let byID = try decoder.decode([String: Runtime].self, from: data)
        return byID.values.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

/// One device from `simctl list devices -j`.
public struct Device: Decodable, Sendable, Equatable {
    public let udid: String
    public let name: String
    public let isAvailable: Bool
    public let dataPath: String?
    public let dataPathSize: Int64?
    /// Runtime identifier the device belongs to (the JSON dictionary key).
    public var runtime: String = ""

    enum CodingKeys: String, CodingKey {
        case udid, name, isAvailable, dataPath, dataPathSize
    }

    /// The device's own folder (the parent of its data folder).
    public var folder: URL? {
        dataPath.map { URL(fileURLWithPath: $0, isDirectory: true).deletingLastPathComponent() }
    }

    static func decodeList(_ data: Data) throws -> [Device] {
        struct List: Decodable { let devices: [String: [Device]] }
        let list = try JSONDecoder().decode(List.self, from: data)
        return list.devices.flatMap { runtime, devices in
            devices.map { var d = $0; d.runtime = runtime; return d }
        }
    }
}
