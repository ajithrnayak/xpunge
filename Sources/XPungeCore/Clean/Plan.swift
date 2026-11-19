import Foundation

/// One thing `clean` will do.
public struct Action: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Permanently remove this file or folder.
        case remove(URL)
        /// Run simctl with these arguments.
        case simctl([String])
    }

    public let category: CategoryID
    public let kind: Kind
    public let label: String
    public let bytes: Int64

    /// Human-readable target: a path or a simctl command line.
    public var target: String {
        switch kind {
        case .remove(let url): url.path
        case .simctl(let args): "xcrun simctl " + args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        }
    }
}

public struct Plan: Sendable {
    public var actions: [Action] = []
    /// Things the user should know: skipped items, protected runtimes, missing Xcode.
    public var notes: [String] = []

    public var totalBytes: Int64 { actions.reduce(0) { $0 + $1.bytes } }
    public var categories: [CategoryID] { Array(Set(actions.map(\.category))).sorted() }

    /// The same plan with actions grouped by category, largest first within each.
    /// Display and execution both use this order so step numbers match.
    public func ordered() -> Plan {
        var copy = self
        copy.actions = categories.flatMap { category in
            actions.filter { $0.category == category }.sorted { $0.bytes > $1.bytes }
        }
        return copy
    }
}

public struct CleanOptions: Sendable {
    /// Runtime builds or identifiers to delete.
    public var runtimes: [String] = []
    /// Select runtimes with no use in this many days (no recorded use counts as unused).
    public var notUsedSinceDays: Int?
    /// Keep this many newest versions in each DeviceSupport folder.
    public var keepLatest: Int?
    public var now: Date = Date()

    public init(runtimes: [String] = [], notUsedSinceDays: Int? = nil, keepLatest: Int? = nil, now: Date = Date()) {
        self.runtimes = runtimes
        self.notUsedSinceDays = notUsedSinceDays
        self.keepLatest = keepLatest
        self.now = now
    }
}

public enum PlanError: Error, Equatable, CustomStringConvertible {
    case scanOnly(CategoryID)
    case runtimesNeedSelector
    case runtimeOptionsWithoutCategory
    case keepLatestWithoutCategory
    case unknownRuntime(String)
    case needsXcode(CategoryID)
    case invalidValue(String)

    public var description: String {
        switch self {
        case .scanOnly(let id):
            "\(id.rawValue) is report-only; xpunge never removes it."
        case .runtimesNeedSelector:
            "runtimes needs --runtime <build|id> or --not-used-since <days>. xpunge never deletes all runtimes at once."
        case .runtimeOptionsWithoutCategory:
            "--runtime and --not-used-since only apply when the runtimes category is named."
        case .keepLatestWithoutCategory:
            "--keep-latest only applies when the device-support category is named."
        case .unknownRuntime(let selector):
            "No installed runtime matches \"\(selector)\". Run `xpunge scan runtimes --details` to list them."
        case .needsXcode(let id):
            "\(id.rawValue) needs a full Xcode for simctl, and none was found. Set DEVELOPER_DIR or install Xcode."
        case .invalidValue(let message):
            message
        }
    }
}
