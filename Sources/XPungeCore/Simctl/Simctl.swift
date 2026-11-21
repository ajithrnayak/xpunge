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
    /// When a runtime was installed, from its disk image's creation date. simctl doesn't report it.
    func installDate(ofRuntimeAt path: String) -> Date?
}

extension SimctlRunning {
    public func installDate(ofRuntimeAt path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.creationDate] as? Date
    }
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
    /// Other installed Xcodes, by display name. Their runtimes are protected too.
    public let otherXcodes: [(name: String, runner: any SimctlRunning)]

    public init(runner: any SimctlRunning, otherXcodes: [(name: String, runner: any SimctlRunning)] = []) {
        self.runner = runner
        self.otherXcodes = otherXcodes
    }

    public func runtimes() throws -> [Runtime] {
        let data = try runner.run(["runtime", "list", "-j"])
        return try Runtime.decodeList(data).map { runtime in
            var runtime = runtime
            runtime.installedAt = runtime.path.flatMap(runner.installDate(ofRuntimeAt:))
            return runtime
        }
    }

    /// Runtime builds one Xcode prefers for its SDKs.
    static func chosenRuntimeBuilds(_ runner: any SimctlRunning) throws -> Set<String> {
        let data = try runner.run(["runtime", "match", "list", "-j"])
        let decoded = try JSONDecoder().decode([String: RuntimeMatch].self, from: data)
        return Set(decoded.values.compactMap(\.chosenRuntimeBuild))
    }

    /// Which installed Xcodes use each runtime build. These are protected from age-based selection.
    public func runtimeUsers() -> RuntimeUsers {
        var users = RuntimeUsers()
        let all: [(name: String, runner: any SimctlRunning)] = [(RuntimeUsers.selected, runner)] + otherXcodes
        for xcode in all {
            do {
                for build in try Self.chosenRuntimeBuilds(xcode.runner) {
                    users.byBuild[build, default: []].append(xcode.name)
                }
            } catch {
                users.unchecked.append(xcode.name)
            }
        }
        return users
    }

    public func devices(in set: DeviceSet) throws -> [Device] {
        let data = try runner.run(set.arguments + ["list", "devices", "-j"])
        return try Device.decodeList(data)
    }
}

/// The Xcodes that use each runtime build, and the Xcodes that couldn't be asked.
public struct RuntimeUsers: Sendable, Equatable {
    public static let selected = "the selected Xcode"
    public var byBuild: [String: [String]] = [:]
    public var unchecked: [String] = []

    public init(byBuild: [String: [String]] = [:], unchecked: [String] = []) {
        self.byBuild = byBuild
        self.unchecked = unchecked
    }

    /// "the selected Xcode and Xcode-26.2.0.app", or nil if nothing uses the build.
    public func describe(_ build: String) -> String? {
        guard let names = byBuild[build], !names.isEmpty else { return nil }
        return names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

struct RuntimeMatch: Decodable {
    var chosenRuntimeBuild: String?
}
