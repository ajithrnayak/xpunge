import Foundation

public struct GuardError: Error, CustomStringConvertible {
    public let action: String
    public let reason: String
    public var description: String { "Refused \(action): \(reason)" }
}

/// The last check before anything is removed. Runs in the planner and again in the executor.
///
/// A remove is allowed only for an item directly inside one of its own category's roots,
/// where that root sits inside the home folder and is not a known important folder.
/// A simctl call is allowed only in the exact shapes xpunge builds, never with `all`.
public enum Guard {
    static let forbiddenPrefixes = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private/etc"]

    /// Folders under home that must never be a root, so their contents are never wiped wholesale.
    static let protectedHomeFolders = [
        "", "Library", "Library/Caches", "Library/Developer", "Library/Developer/Xcode",
        "Library/Developer/Xcode/UserData", "Library/Developer/CoreSimulator", "Library/Application Support",
        "Desktop", "Documents", "Downloads", "Developer", "Projects", "Movies", "Music", "Pictures",
    ]

    public static func check(_ action: Action, category: Category, home: URL) throws {
        guard action.category == category.id else {
            throw GuardError(action: action.target, reason: "action and category do not match")
        }
        switch action.kind {
        case .remove(let url):
            try checkRemove(url, category: category, home: home, target: action.target)
        case .simctl(let args):
            try checkSimctl(args, category: category, target: action.target)
        }
    }

    private static func checkRemove(_ url: URL, category: Category, home: URL, target: String) throws {
        func refuse(_ reason: String) -> GuardError { GuardError(action: target, reason: reason) }

        switch category.removal {
        case .contents, .files: break
        default: throw refuse("\(category.id.rawValue) is not removed by deleting files")
        }

        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else { throw refuse("invalid name") }
        if case .files(let suffixes) = category.removal, !suffixes.contains(where: name.hasSuffix) {
            throw refuse("file type not allowed for this category")
        }

        let resolvedHome = home.resolvingSymlinksInPath().standardizedFileURL.path
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path

        let matchingRoot = category.roots.first {
            $0.resolvingSymlinksInPath().standardizedFileURL.path == parent
        }
        guard let root = matchingRoot else { throw refuse("not directly inside a \(category.id.rawValue) folder") }

        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard rootPath.hasPrefix(resolvedHome + "/") else { throw refuse("folder is outside the home folder") }
        let relative = String(rootPath.dropFirst(resolvedHome.count + 1))
        if protectedHomeFolders.contains(relative) { throw refuse("\(rootPath) is a protected folder") }
        if relative.hasPrefix("Library/Developer/Xcode/UserData") {
            throw refuse("UserData holds settings, snippets and themes")
        }

        // Belt and braces: the root is inside home, but never act on system locations whatever home is.
        let itemPath = parent + "/" + name
        for prefix in forbiddenPrefixes where itemPath.hasPrefix(prefix + "/") {
            throw refuse("inside \(prefix)")
        }
    }

    private static func checkSimctl(_ args: [String], category: Category, target: String) throws {
        func refuse(_ reason: String) -> GuardError { GuardError(action: target, reason: reason) }

        if args.contains(where: { $0.caseInsensitiveCompare("all") == .orderedSame }) {
            throw refuse("xpunge never passes 'all' to simctl")
        }
        switch category.removal {
        case .unavailableDevices(let set):
            guard args == set.arguments + ["delete", "unavailable"] else { throw refuse("unexpected simctl command") }
        case .runtimes:
            guard args.count == 3, args[0] == "runtime", args[1] == "delete",
                  args[2].range(of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#,
                                options: .regularExpression) != nil
            else { throw refuse("runtimes are deleted only by their UUID") }
        default:
            throw refuse("\(category.id.rawValue) is not removed through simctl")
        }
    }
}
