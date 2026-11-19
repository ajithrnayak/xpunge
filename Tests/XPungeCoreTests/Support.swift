import Foundation
@testable import XPungeCore

/// A throwaway home folder under the system temp directory.
final class TempHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xpunge-tests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // Only ever removes the temp folder this object created.
        if url.path.contains("/xpunge-tests-") { try? FileManager.default.removeItem(at: url) }
    }

    var env: Environment { Environment(home: url, applications: url.appendingPathComponent("Applications")) }

    @discardableResult
    func file(_ relative: String, bytes: Int = 4096) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: bytes).write(to: file)
        return file
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let folder = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }
}

/// Serves the simctl JSON captured from Xcode 26.2 on 2026-11-20 and records every call.
final class FakeSimctl: SimctlRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    private let home: URL?

    /// - Parameter home: replaces the anonymised `/Users/tester` in fixture paths.
    init(home: URL? = nil) {
        self.home = home
    }

    var calls: [[String]] { lock.withLock { _calls } }
    var destructiveCalls: [[String]] { calls.filter { $0.contains("delete") } }

    func run(_ arguments: [String]) throws -> Data {
        lock.withLock { _calls.append(arguments) }
        let fixture: String
        switch arguments {
        case ["runtime", "list", "-j"]: fixture = "runtime-list"
        case ["runtime", "match", "list", "-j"]: fixture = "runtime-match-list"
        case ["list", "devices", "-j"]: fixture = "devices-default"
        case ["--set", "previews", "list", "devices", "-j"]: fixture = "devices-previews"
        case ["--set", "testing", "list", "devices", "-j"]: fixture = "devices-testing"
        case _ where arguments.contains("delete"): return Data()
        default: throw SimctlError(arguments: arguments, status: 1, message: "not faked")
        }
        let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!
        var text = try String(contentsOf: url, encoding: .utf8)
        if let home {
            text = text.replacingOccurrences(of: #"\/Users\/tester"#, with: home.path.replacingOccurrences(of: "/", with: #"\/"#))
                .replacingOccurrences(of: "/Users/tester", with: home.path)
        }
        return Data(text.utf8)
    }
}

/// Records removals without touching the disk.
final class RecordingRemover: Remover, @unchecked Sendable {
    private let lock = NSLock()
    private var _removed: [URL] = []
    var removed: [URL] { lock.withLock { _removed } }
    func remove(_ url: URL) throws { lock.withLock { _removed.append(url) } }
}

/// 2026-11-20, the day the fixtures were captured.
let fixtureDate = ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z")!

let derivedData = "Library/Developer/Xcode/DerivedData"
