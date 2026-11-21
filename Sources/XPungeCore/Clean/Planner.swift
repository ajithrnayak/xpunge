import Foundation

/// Turns a category selection into a list of actions. Never deletes anything.
public struct Planner: Sendable {
    public let env: Environment
    public let simctl: SimctlQueries?

    public init(env: Environment, simctl: SimctlQueries?) {
        self.env = env
        self.simctl = simctl
    }

    /// - Parameter named: categories named on the command line; empty means the default set.
    public func plan(named: [CategoryID], options: CleanOptions = CleanOptions()) throws -> Plan {
        let catalog = Catalog.categories(in: env)
        let selected = try select(named: named, options: options, catalog: catalog)

        var plan = Plan()
        for category in selected {
            try add(category, options: options, to: &plan)
        }
        for action in plan.actions {
            let category = catalog.first { $0.id == action.category }!
            try Guard.check(action, category: category, home: env.home)
        }
        return plan
    }

    func select(named: [CategoryID], options: CleanOptions, catalog: [Category]) throws -> [Category] {
        if options.notUsedSinceDays.map({ $0 < 0 }) == true {
            throw PlanError.invalidValue("--not-used-since must be 0 or more days.")
        }
        if options.keepLatest.map({ $0 < 0 }) == true {
            throw PlanError.invalidValue("--keep-latest must be 0 or more.")
        }
        let hasRuntimeOptions = !options.runtimes.isEmpty || options.notUsedSinceDays != nil
        if hasRuntimeOptions && !named.contains(.runtimes) { throw PlanError.runtimeOptionsWithoutCategory }
        if named.contains(.runtimes) && !hasRuntimeOptions { throw PlanError.runtimesNeedSelector }
        if options.keepLatest != nil && !named.contains(.deviceSupport) { throw PlanError.keepLatestWithoutCategory }

        if named.isEmpty {
            return catalog.filter { $0.policy == .byDefault }
        }
        return try catalog.filter { named.contains($0.id) }.map { category in
            if category.policy == .scanOnly { throw PlanError.scanOnly(category.id) }
            return category
        }
    }

    private func add(_ category: Category, options: CleanOptions, to plan: inout Plan) throws {
        switch category.removal {
        case .contents:
            var items = Folder.children(of: category.roots)
            if category.id == .deviceSupport, let keep = options.keepLatest {
                let kept = DeviceSupport.newest(keep, in: category.roots)
                if !kept.isEmpty {
                    plan.notes.append("Keeping \(kept.count) device support folder(s): "
                        + kept.map(\.lastPathComponent).joined(separator: ", "))
                }
                items.removeAll { kept.contains($0) }
            }
            if category.id == .archives, !items.isEmpty {
                plan.notes.append("Archives hold the dSYMs needed to symbolicate crash reports from shipped builds.")
            }
            plan.actions += items.map {
                Action(category: category.id, kind: .remove($0), label: Folder.label(for: $0, roots: category.roots),
                       bytes: Sizer.size(of: $0))
            }

        case .files(let suffixes):
            plan.actions += Folder.files(in: category.roots, suffixes: suffixes).map {
                Action(category: category.id, kind: .remove($0), label: $0.lastPathComponent, bytes: Sizer.size(of: $0))
            }

        case .unavailableDevices(let set):
            guard let simctl else {
                plan.notes.append("Skipped \(category.id.rawValue): no full Xcode found for simctl.")
                return
            }
            let unavailable = try simctl.devices(in: set).filter { !$0.isAvailable }
            guard !unavailable.isEmpty else { return }
            let bytes = unavailable.reduce(0) { $0 + DeviceSize.of($1) }
            plan.actions.append(Action(
                category: category.id, kind: .simctl(set.arguments + ["delete", "unavailable"]),
                label: "\(unavailable.count) unavailable device\(unavailable.count == 1 ? "" : "s")", bytes: bytes
            ))

        case .runtimes:
            guard let simctl else { throw PlanError.needsXcode(.runtimes) }
            let runtimes = try simctl.runtimes()
            let users = simctl.runtimeUsers()
            for runtime in try RuntimeSelection.select(from: runtimes, users: users, options: options, notes: &plan.notes) {
                plan.actions.append(Action(
                    category: .runtimes, kind: .simctl(["runtime", "delete", runtime.identifier]),
                    label: "\(runtime.displayName) (\(runtime.build))", bytes: runtime.sizeBytes
                ))
            }

        case .none:
            return
        }
    }
}

enum RuntimeSelection {
    static func select(from runtimes: [Runtime], users: RuntimeUsers, options: CleanOptions,
                       notes: inout [String]) throws -> [Runtime] {
        var selected: [Runtime] = []

        for selector in options.runtimes {
            let matches = runtimes.filter {
                $0.identifier.caseInsensitiveCompare(selector) == .orderedSame
                    || $0.build.caseInsensitiveCompare(selector) == .orderedSame
            }
            guard !matches.isEmpty else { throw PlanError.unknownRuntime(selector) }
            selected += matches
        }

        if let days = options.notUsedSinceDays {
            for name in users.unchecked {
                notes.append("Couldn't check which runtimes \(name) uses, so its runtimes may be selected. Check the list before cleaning.")
            }
            let cutoff = options.now.addingTimeInterval(-Double(days) * 86_400)
            for runtime in runtimes where (runtime.lastActivity ?? .distantPast) < cutoff {
                if let user = users.describe(runtime.build) {
                    notes.append("Keeping \(runtime.displayName) (\(runtime.build)): \(user) \(users.byBuild[runtime.build]!.count > 1 ? "use" : "uses") it. Name it with --runtime to remove it anyway.")
                    continue
                }
                selected.append(runtime)
            }
        }

        var seen = Set<String>()
        return selected.filter { runtime in
            guard seen.insert(runtime.identifier).inserted else { return false }
            if !runtime.deletable {
                notes.append("Skipping \(runtime.displayName) (\(runtime.build)): simctl reports it cannot be deleted. See the project README on orphaned runtimes.")
                return false
            }
            return true
        }
    }
}

enum DeviceSupport {
    /// Folder names look like "16.6 (20F75) arm64e", "iPhone13,2 16.7 (20H19)" or "Watch3,2 8.7.1 (19U67)".
    static func version(of name: String) -> [Int]? {
        guard let match = name.range(of: #"\d+(\.\d+)+(?= \()"#, options: .regularExpression) else { return nil }
        return name[match].split(separator: ".").compactMap { Int($0) }
    }

    /// The entries holding the newest `count` distinct versions in each root.
    static func newest(_ count: Int, in roots: [URL]) -> [URL] {
        roots.flatMap { root -> [URL] in
            let entries = Folder.children(of: [root])
            let versions = Set(entries.compactMap { version(of: $0.lastPathComponent) })
                .sorted { $0.lexicographicallyPrecedes($1) }
                .suffix(count)
            return entries.filter { entry in
                version(of: entry.lastPathComponent).map(versions.contains) ?? false
            }
        }
    }
}
