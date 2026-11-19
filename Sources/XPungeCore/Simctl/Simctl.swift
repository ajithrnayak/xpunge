import Foundation

public struct SimctlError: Error, CustomStringConvertible {
    public let arguments: [String]
    public let status: Int32
    public let message: String
    public var description: String {
        "simctl \(arguments.joined(separator: " ")) failed (\(status)): \(message)"
    }
}

/// Runs simctl. Injected so tests never touch the real simulator service.
public protocol SimctlRunning: Sendable {
    func run(_ arguments: [String]) throws -> Data
}

/// Runs `xcrun simctl` against a specific Xcode via DEVELOPER_DIR, leaving xcode-select alone.
public struct Simctl: SimctlRunning {
    public let developerDir: URL

    public init(developerDir: URL) {
        self.developerDir = developerDir
    }

    public func run(_ arguments: [String]) throws -> Data {
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = developerDir.path
        let result = try ProcessRunner.run("/usr/bin/xcrun", ["simctl"] + arguments, environment: environment)
        guard result.status == 0 else {
            throw SimctlError(
                arguments: arguments, status: result.status,
                message: String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.stdout
    }
}

/// Read-only queries built on a runner.
public struct SimctlQueries: Sendable {
    public let runner: any SimctlRunning

    public init(runner: any SimctlRunning) {
        self.runner = runner
    }

    public func runtimes() throws -> [Runtime] {
        let data = try runner.run(["runtime", "list", "-j"])
        return try Runtime.decodeList(data)
    }

    /// Runtime builds the selected Xcode prefers for its SDKs. These are protected from age-based selection.
    public func chosenRuntimeBuilds() throws -> Set<String> {
        let data = try runner.run(["runtime", "match", "list", "-j"])
        let decoded = try JSONDecoder().decode([String: RuntimeMatch].self, from: data)
        return Set(decoded.values.compactMap(\.chosenRuntimeBuild))
    }

    public func devices(in set: DeviceSet) throws -> [Device] {
        let data = try runner.run(set.arguments + ["list", "devices", "-j"])
        return try Device.decodeList(data)
    }
}

struct RuntimeMatch: Decodable {
    var chosenRuntimeBuild: String?
}
