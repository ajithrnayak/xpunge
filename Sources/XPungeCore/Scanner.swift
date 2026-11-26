import Foundation

public struct Detail: Encodable, Sendable, Equatable {
    public let name: String
    public let bytes: Int64
    public let note: String?
}

public struct CategoryReport: Encodable, Sendable {
    public let id: CategoryID
    public let title: String
    public let policy: Policy
    /// Total size on disk; nil when it could not be measured (e.g. runtimes without Xcode).
    public let bytes: Int64?
    /// What cleaning this category with default options would free; nil when it depends on options.
    public let reclaimable: Int64?
    public let note: String?
    public let details: [Detail]
}

/// Measures every category. Read-only.
public struct Scanner: Sendable {
    public let env: Environment
    public let simctl: SimctlQueries?
    public let now: Date

    public init(env: Environment, simctl: SimctlQueries?, now: Date = Date()) {
        self.env = env
        self.simctl = simctl
        self.now = now
    }

    public func scan(_ ids: [CategoryID] = CategoryID.allCases) -> [CategoryReport] {
        Catalog.categories(in: env)
            .filter { ids.contains($0.id) }
            .map(report)
            .sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }

    func report(_ category: Category) -> CategoryReport {
        switch category.removal {
        case .contents, .files, .none:
            return folderReport(category)
        case .unavailableDevices(let set):
            return deviceReport(category, set: set)
        case .runtimes:
            return runtimeReport(category)
        }
    }

    private func folderReport(_ category: Category) -> CategoryReport {
        var details: [Detail]
        switch category.removal {
        case .files(let suffixes):
            details = Folder.files(in: category.roots, suffixes: suffixes).map {
                Detail(name: $0.lastPathComponent, bytes: Sizer.size(of: $0),
                       note: $0.lastPathComponent.hasSuffix(".aria2") ? "unfinished download marker" : nil)
            }
        case .none where category.id == .xcodeApps:
            details = category.roots.map { Detail(name: $0.lastPathComponent, bytes: Sizer.size(of: $0), note: nil) }
        default:
            details = Folder.children(of: category.roots).map {
                Detail(name: Folder.label(for: $0, roots: category.roots), bytes: Sizer.size(of: $0), note: nil)
            }
        }
        details.sort { $0.bytes > $1.bytes }
        let total = details.reduce(0) { $0 + $1.bytes }

        var note: String?
        if category.id == .derivedData,
           let cache = details.first(where: { $0.name == "CompilationCache.noindex" }) {
            note = "includes compilation cache (\(ByteFormat.string(cache.bytes)))"
        } else if category.id == .xcodeApps {
            note = details.isEmpty ? nil : "\(details.count) installed"
        } else if category.id == .xcodesDownloads, details.contains(where: { $0.name.hasSuffix(".aria2") }) {
            note = "includes unfinished downloads"
        }
        let reclaimable: Int64? = category.policy == .scanOnly ? nil : total
        return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                              bytes: total, reclaimable: reclaimable, note: note, details: details)
    }

    private func deviceReport(_ category: Category, set: DeviceSet) -> CategoryReport {
        let total = Sizer.size(of: category.roots)
        guard let simctl else {
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: total, reclaimable: nil, note: "needs Xcode to find unavailable devices", details: [])
        }
        do {
            let unavailable = try simctl.devices(in: set).filter { !$0.isAvailable }
            let details = unavailable.map {
                Detail(name: $0.name, bytes: DeviceSize.of($0), note: runtimeLabel($0.runtime))
            }.sorted { $0.bytes > $1.bytes }
            let reclaimable = details.reduce(0) { $0 + $1.bytes }
            let note = unavailable.isEmpty ? nil : "\(unavailable.count) unavailable"
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: total, reclaimable: reclaimable, note: note, details: details)
        } catch {
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: total, reclaimable: nil, note: "simctl failed: \(error)", details: [])
        }
    }

    private func runtimeReport(_ category: Category) -> CategoryReport {
        guard let simctl else {
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: nil, reclaimable: nil, note: "needs Xcode (sizes come from simctl only)", details: [])
        }
        do {
            let runtimes = try simctl.runtimes(dyldCache: env.simulatorDyldCache)
            let users = simctl.runtimeUsers()
            let details = runtimes.map { runtime in
                var notes = [RuntimeAge.describe(runtime, now: now)]
                if let user = users.describe(runtime.build) { notes.append("used by \(user)") }
                if !runtime.deletable { notes.append("simctl cannot delete it") }
                if let dyld = DyldCache.note(runtime) { notes.append(dyld) }
                return Detail(name: runtime.label, bytes: runtime.totalBytes,
                              note: notes.joined(separator: ", "))
            }
            let total = runtimes.reduce(0) { $0 + $1.totalBytes }
            let unused = runtimes.filter { $0.lastUsedAt == nil }.count
            var note = "\(runtimes.count) runtime\(runtimes.count == 1 ? "" : "s")"
            if unused > 0 { note += ", \(unused) with no recorded use" }
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: total, reclaimable: nil, note: note, details: details)
        } catch {
            return CategoryReport(id: category.id, title: category.title, policy: category.policy,
                                  bytes: nil, reclaimable: nil, note: "simctl failed: \(error)", details: [])
        }
    }

    private func runtimeLabel(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
    }
}

enum DeviceSize {
    /// Measured from the device folder when it exists; otherwise simctl's own figure.
    static func of(_ device: Device) -> Int64 {
        if let folder = device.folder, FileManager.default.fileExists(atPath: folder.path) {
            return Sizer.size(of: folder)
        }
        return device.dataPathSize ?? 0
    }
}

enum DyldCache {
    /// "includes 3.8 GB dyld cache", or nil when the runtime has none.
    static func note(_ runtime: Runtime) -> String? {
        guard let bytes = runtime.dyldCacheBytes, bytes > 0 else { return nil }
        return "includes \(ByteFormat.string(bytes)) dyld cache"
    }
}

enum RuntimeAge {
    static func describe(_ runtime: Runtime, now: Date) -> String {
        if let lastUsed = runtime.lastUsedAt { return "last used \(ago(lastUsed, now: now))" }
        if let installed = runtime.installedAt { return "no recorded use, installed \(ago(installed, now: now))" }
        return "no recorded use"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return "\(formatter.string(from: date)), \(days) day\(days == 1 ? "" : "s") ago"
    }
}

enum Folder {
    /// The item's name, prefixed with its folder when the category has several roots,
    /// so "Cache.db" in two caches can be told apart.
    static func label(for item: URL, roots: [URL]) -> String {
        guard roots.count > 1 else { return item.lastPathComponent }
        return item.deletingLastPathComponent().lastPathComponent + "/" + item.lastPathComponent
    }

    /// Items directly inside each existing root, hidden files included.
    static func children(of roots: [URL]) -> [URL] {
        roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: []
            )) ?? []).sorted { $0.path < $1.path }
        }
    }

    /// Regular files directly inside each root whose name ends with one of the suffixes.
    static func files(in roots: [URL], suffixes: [String]) -> [URL] {
        children(of: roots).filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && suffixes.contains(where: url.lastPathComponent.hasSuffix)
        }
    }
}

public enum ByteFormat {
    /// Decimal units, matching Finder and System Settings.
    public static func string(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
