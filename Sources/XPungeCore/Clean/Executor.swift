import Foundation

/// Removes a file or folder. Injected so tests can record instead of delete.
public protocol Remover: Sendable {
    func remove(_ url: URL) throws
}

/// Permanent removal. The Trash would not free space until it is emptied.
public struct FileRemover: Remover {
    public init() {}
    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

public struct ActionResult: Sendable {
    public let action: Action
    public let error: String?
    public var succeeded: Bool { error == nil }
}

/// Runs a plan one action at a time. Every action passes the Guard again first.
public struct Executor: Sendable {
    public let env: Environment
    public let remover: any Remover
    public let simctl: (any SimctlRunning)?

    public init(env: Environment, remover: any Remover = FileRemover(), simctl: (any SimctlRunning)?) {
        self.env = env
        self.remover = remover
        self.simctl = simctl
    }

    public func execute(_ plan: Plan, progress: (ActionResult) -> Void = { _ in }) -> [ActionResult] {
        let catalog = Catalog.categories(in: env)
        return plan.actions.map { action in
            let result = ActionResult(action: action, error: perform(action, catalog: catalog))
            progress(result)
            return result
        }
    }

    private func perform(_ action: Action, catalog: [Category]) -> String? {
        do {
            guard let category = catalog.first(where: { $0.id == action.category }) else {
                return "unknown category"
            }
            try Guard.check(action, category: category, home: env.home)
            switch action.kind {
            case .remove(let url):
                // Already gone counts as done. lstat-style check so a dangling symlink is still removed.
                guard (try? url.checkResourceIsReachable()) == true
                    || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
                else { return nil }
                try remover.remove(url)
            case .simctl(let args):
                guard let simctl else { return "no full Xcode found for simctl" }
                _ = try simctl.run(args)
            }
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

/// Apps that should be closed before cleaning (Apple DTS advice).
public enum RunningApps {
    public static let watched = ["Xcode", "Simulator"]

    public static func running() -> [String] {
        watched.filter { name in
            (try? ProcessRunner.run("/usr/bin/pgrep", ["-x", name]))?.status == 0
        }
    }
}
