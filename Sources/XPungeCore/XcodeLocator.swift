import Foundation

/// Finds a full Xcode to run simctl from.
///
/// `xcode-select` often points at the Command Line Tools, which have no simctl,
/// so xpunge looks further instead of failing.
public enum XcodeLocator {
    /// Order: DEVELOPER_DIR, then `xcode-select -p`, then the newest /Applications/Xcode*.app.
    public static func locate(
        variables: [String: String],
        selectedPath: String?,
        applications: URL
    ) -> URL? {
        var candidates: [URL] = []
        if let dir = variables["DEVELOPER_DIR"], !dir.isEmpty {
            candidates.append(URL(fileURLWithPath: dir, isDirectory: true))
        }
        if let selectedPath, !selectedPath.isEmpty {
            candidates.append(URL(fileURLWithPath: selectedPath, isDirectory: true))
        }
        let apps = Catalog.xcodeApps(in: applications)
            .sorted { version(of: $0).lexicographicallyPrecedes(version(of: $1)) }
            .reversed()
        candidates += apps.map { $0.appendingPathComponent("Contents/Developer", isDirectory: true) }

        return candidates.first(where: hasSimctl)
    }

    /// Every installed Xcode app with simctl, except the one at `excluding` (a developer directory).
    public static func otherInstalled(applications: URL, excluding developerDir: URL?) -> [URL] {
        let excluded = developerDir?.resolvingSymlinksInPath().standardizedFileURL.path
        return Catalog.xcodeApps(in: applications).filter { app in
            let dir = app.appendingPathComponent("Contents/Developer", isDirectory: true)
            return hasSimctl(dir) && dir.resolvingSymlinksInPath().standardizedFileURL.path != excluded
        }
    }

    /// The developer directory xcode-select points at, if any.
    public static func xcodeSelectPath() -> String? {
        guard let result = try? ProcessRunner.run("/usr/bin/xcode-select", ["-p"]), result.status == 0 else {
            return nil
        }
        return String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasSimctl(_ developerDir: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: developerDir.appendingPathComponent("usr/bin/simctl").path)
    }

    static func version(of app: URL) -> [Int] {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let short = info["CFBundleShortVersionString"] as? String else { return [] }
        return short.split(separator: ".").compactMap { Int($0) }
    }
}
