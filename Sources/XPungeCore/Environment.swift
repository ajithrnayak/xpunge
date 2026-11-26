import Foundation

/// Everything xpunge reads from the outside world, so tests can point it at a temp folder.
public struct Environment: Sendable {
    /// The user's home folder. Every cleanable path is resolved against this.
    public var home: URL
    /// Folder that holds Xcode apps (normally /Applications).
    public var applications: URL
    /// Process environment (used for DEVELOPER_DIR).
    public var variables: [String: String]
    /// Custom locations set in Xcode > Settings > Locations, if any.
    public var customDerivedData: URL?
    public var customArchives: URL?
    /// CoreSimulator's per-runtime dyld shared caches. Only measured, never removed by xpunge:
    /// CoreSimulator deletes a runtime's cache when the runtime is deleted.
    public var simulatorDyldCache: URL

    public init(
        home: URL,
        applications: URL = URL(fileURLWithPath: "/Applications"),
        variables: [String: String] = [:],
        customDerivedData: URL? = nil,
        customArchives: URL? = nil,
        simulatorDyldCache: URL = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld", isDirectory: true)
    ) {
        self.home = home
        self.applications = applications
        self.variables = variables
        self.customDerivedData = customDerivedData
        self.customArchives = customArchives
        self.simulatorDyldCache = simulatorDyldCache
    }

    /// The real environment of the current user.
    public static func current() -> Environment {
        let xcodeDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode")
        func customPath(_ key: String) -> URL? {
            // Key names are not yet confirmed against a Mac with a custom location set.
            guard let path = xcodeDefaults?.string(forKey: key), path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Environment(
            home: FileManager.default.homeDirectoryForCurrentUser,
            variables: ProcessInfo.processInfo.environment,
            customDerivedData: customPath("IDECustomDerivedDataLocation"),
            customArchives: customPath("IDECustomDistributionArchivesLocation")
        )
    }

    func homePath(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }
}
