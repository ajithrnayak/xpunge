import Foundation

/// Stable identifiers used on the command line and in JSON output.
public enum CategoryID: String, CaseIterable, Codable, Sendable, Comparable {
    case derivedData = "derived-data"
    case xcodeCache = "xcode-cache"
    case swiftpmCache = "swiftpm-cache"
    case cocoapodsCache = "cocoapods-cache"
    case carthageCache = "carthage-cache"
    case documentation
    case simulatorCaches = "simulator-caches"
    case simulatorDevices = "simulator-devices"
    case previews
    case testDevices = "test-devices"
    case runtimes
    case deviceSupport = "device-support"
    case archives
    case xcodesDownloads = "xcodes-downloads"
    case playgroundDevices = "playground-devices"
    case xcodeApps = "xcode-apps"

    public static func < (lhs: CategoryID, rhs: CategoryID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// When a category may be cleaned.
public enum Policy: String, Codable, Sendable {
    /// Included in a plain `xpunge clean`.
    case byDefault = "default"
    /// Cleaned only when named on the command line.
    case namedOnly = "named"
    /// Reported by `scan`, never cleaned.
    case scanOnly = "scan-only"
}

/// A simulator device set, as `simctl --set` understands it.
public enum DeviceSet: Sendable, Equatable {
    case standard
    case previews
    case testing

    /// Arguments that select this set; empty for the default set.
    public var arguments: [String] {
        switch self {
        case .standard: []
        case .previews: ["--set", "previews"]
        case .testing: ["--set", "testing"]
        }
    }
}

/// How a category is removed.
public enum Removal: Sendable, Equatable {
    /// Remove every item directly inside each root, keeping the roots themselves.
    case contents
    /// Remove files directly inside the roots whose name ends with one of these suffixes.
    case files(suffixes: [String])
    /// `simctl [--set …] delete unavailable`.
    case unavailableDevices(DeviceSet)
    /// `simctl runtime delete <identifier>`, one call per selected runtime.
    case runtimes
    /// Nothing; report only.
    case none
}

public struct Category: Sendable {
    public let id: CategoryID
    public let title: String
    public let policy: Policy
    public let removal: Removal
    /// Folders measured by `scan`, and the only folders `clean` may remove items from.
    public let roots: [URL]
    /// Short explanation shown in `scan --details` and the clean plan.
    public let about: String
}
