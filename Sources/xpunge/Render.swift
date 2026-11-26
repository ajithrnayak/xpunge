import Foundation
import XPungeCore

/// Whether stdout is a terminal that wants color, and how wide it is.
struct Terminal {
    let color: Bool
    let width: Int?
    /// Interjections and emoji on success lines. Only in a terminal; XPUNGE_PLAIN=1 turns them off.
    let playful: Bool

    static func current() -> Terminal {
        let environment = ProcessInfo.processInfo.environment
        let isTTY = isatty(STDOUT_FILENO) == 1
        let color = isTTY && environment["NO_COLOR"] == nil && environment["TERM"] != "dumb"
        let playful = isTTY && environment["TERM"] != "dumb" && (environment["XPUNGE_PLAIN"] ?? "").isEmpty

        var size = winsize()
        var width: Int?
        if isTTY, ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            width = Int(size.ws_col)
        } else if let columns = environment["COLUMNS"].flatMap(Int.init), columns > 0 {
            width = columns
        }
        return Terminal(color: color, width: width, playful: playful)
    }

    /// A green success line, starting with a random interjection and emoji when playful.
    func cheer(_ moment: Cheer.Moment, _ text: String) -> String {
        green((playful ? Cheer.prefix(moment) : "") + text)
    }

    func green(_ text: String) -> String { color ? "\u{1B}[32m\(text)\u{1B}[0m" : text }
    func dim(_ text: String) -> String { color ? "\u{1B}[2m\(text)\u{1B}[0m" : text }
    func red(_ text: String) -> String { color ? "\u{1B}[31m\(text)\u{1B}[0m" : text }
}

enum Render {
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func size(_ bytes: Int64) -> String { ByteFormat.string(bytes) }

    // MARK: scan

    /// - Parameter complete: every category was scanned, so the total is all of Xcode's usage.
    static func scanTable(_ reports: [CategoryReport], details: Bool, complete: Bool, xcodeFound: Bool,
                          terminal: Terminal) -> String {
        var table = TextTable(title: "xpunge scan", columns: [
            .init("Category", flexible: details),
            .init("Size", .right),
            .init("Clean"),
            .init("Note", flexible: true),
        ])

        for report in reports {
            var note = report.note ?? ""
            if let reclaimable = report.reclaimable, reclaimable > 0,
               [.simulatorDevices, .previews, .testDevices].contains(report.id) {
                note += " (\(size(reclaimable)))"
            }
            table.add([report.id.rawValue, report.bytes.map(size) ?? "-", policyLabel(report.policy), note])
            if details && !report.details.isEmpty {
                for detail in report.details {
                    table.add(["  " + detail.name, size(detail.bytes), "", detail.note ?? ""], .dim)
                }
                table.addSeparator()
            }
        }

        let total = reports.compactMap(\.bytes).reduce(0, +)
        let defaults = reports.filter { $0.policy == .byDefault }
        let defaultTotal = defaults.compactMap(\.reclaimable).reduce(0, +)
        // What a plain `xpunge clean` would do, or nil when no default category was scanned.
        let plainClean: String? = defaults.isEmpty ? nil
            : defaultTotal > 0 ? "a plain clean frees about \(size(defaultTotal))"
            : "nothing left to clean by default"
        table.addSeparator()
        table.add(["Total", size(total), "", plainClean ?? ""], .bold)

        var lines = [table.render(maxWidth: terminal.width, color: terminal.color), ""]
        let subject = complete ? "Xcode is using \(size(total)) here" : "These categories use \(size(total))"
        let spotless = !defaults.isEmpty && defaultTotal == 0
        lines.append(terminal.cheer(spotless ? .spotless : .scanned, subject + (plainClean.map { "; \($0)." } ?? ".")))
        let named = reports.filter { $0.policy == .namedOnly && ($0.bytes ?? 0) > 0 }
        if !named.isEmpty {
            lines.append("Cleaned only when named: "
                + named.map { "\($0.id.rawValue) (\(size($0.bytes ?? 0)))" }.joined(separator: ", ") + ".")
        }
        if !xcodeFound {
            lines.append("No full Xcode found, so simulator runtimes and device sets are partly unmeasured. "
                + "Set DEVELOPER_DIR to an Xcode's Contents/Developer.")
        }
        if defaultTotal > 0 {
            lines.append("Preview a clean with `xpunge clean --dry-run`.")
        } else if !named.isEmpty && !details {
            lines.append("See what's in them with `xpunge scan \(named.map(\.id.rawValue).joined(separator: " ")) --details`.")
        }
        return lines.joined(separator: "\n")
    }

    private static func policyLabel(_ policy: Policy) -> String {
        switch policy {
        case .byDefault: "default"
        case .namedOnly: "by name"
        case .scanOnly: "report only"
        }
    }

    // MARK: clean

    /// Expects `plan.ordered()`, so the numbers match the summary after execution.
    static func plan(_ plan: Plan, dryRun: Bool, terminal: Terminal) -> String {
        var lines: [String] = []
        if plan.actions.isEmpty {
            lines.append(terminal.cheer(.spotless, "Nothing to clean."))
        } else {
            var table = TextTable(title: dryRun ? "xpunge clean: dry run" : "xpunge clean: plan", columns: [
                .init("#", .right), .init("Category"), .init("Item", flexible: true), .init("Size", .right),
            ])
            var previous: CategoryID?
            for (index, action) in plan.actions.enumerated() {
                if let previous, previous != action.category { table.addSeparator() }
                previous = action.category
                table.add(["\(index + 1)", action.category.rawValue, action.label, size(action.bytes)])
                if let note = action.note {
                    table.add(["", "", note, ""], .dim)
                }
                if case .simctl = action.kind {
                    table.add(["", "", "runs: \(action.target)", ""], .dim)
                }
            }
            table.addSeparator()
            table.add(["", "Total", "\(plan.actions.count) item(s)", size(plan.totalBytes)], .bold)
            lines.append(table.render(maxWidth: terminal.width, color: terminal.color))
        }
        if !plan.notes.isEmpty {
            lines.append("")
            lines += plan.notes.map { "Note: \($0)" }
        }
        if dryRun && !plan.actions.isEmpty {
            lines.append("")
            lines.append(terminal.cheer(.previewed, "Nothing was removed. Run without --dry-run to clean."))
        }
        return lines.joined(separator: "\n")
    }

    static func progress(_ result: ActionResult, terminal: Terminal) -> String {
        let bytes = size(result.action.bytes).leftPadded(to: 10)
        if result.succeeded {
            return "  " + terminal.green("done") + "    \(bytes)  \(result.action.label)"
        }
        return "  " + terminal.red("failed") + "  \(bytes)  \(result.action.label)"
    }

    static func summary(_ results: [ActionResult], terminal: Terminal) -> String {
        var table = TextTable(title: "xpunge clean summary", columns: [
            .init("#", .right), .init("Category"), .init("Item", flexible: true), .init("Size", .right), .init("Result"),
        ])
        var previous: CategoryID?
        for (index, result) in results.enumerated() {
            if let previous, previous != result.action.category { table.addSeparator() }
            previous = result.action.category
            table.add([
                "\(index + 1)", result.action.category.rawValue, result.action.label, size(result.action.bytes),
                result.succeeded ? "done" : "failed",
            ], result.succeeded ? .normal : .bad)
        }
        let done = results.filter(\.succeeded)
        let freed = done.reduce(0) { $0 + $1.action.bytes }
        table.addSeparator()
        table.add(["", "Freed", "\(done.count) of \(results.count) item(s)", size(freed), ""], .bold)

        var lines = ["", table.render(maxWidth: terminal.width, color: terminal.color)]
        let failures = results.enumerated().filter { !$0.element.succeeded }
        if !failures.isEmpty {
            lines.append("")
            lines += failures.map { terminal.red("#\($0.offset + 1) failed: ") + ($0.element.error ?? "") }
        }
        lines.append("")
        if failures.isEmpty {
            lines.append(terminal.cheer(.cleaned, "xpunge freed about \(size(freed))."))
        } else {
            lines.append(terminal.red("xpunge freed about \(size(freed)), but \(failures.count) item(s) failed."))
        }
        return lines.joined(separator: "\n")
    }
}

/// JSON shape for `clean --json`.
struct PlanOutput: Encodable {
    struct Item: Encodable {
        let category: String
        let kind: String
        let target: String
        let label: String
        let bytes: Int64
        let error: String?
    }

    let dryRun: Bool
    let totalBytes: Int64
    let actions: [Item]
    let notes: [String]

    init(plan: Plan, dryRun: Bool, results: [ActionResult]?) {
        self.dryRun = dryRun
        self.totalBytes = plan.totalBytes
        self.notes = plan.notes
        self.actions = plan.actions.enumerated().map { index, action in
            let kind: String
            switch action.kind {
            case .remove: kind = "remove"
            case .simctl: kind = "simctl"
            }
            return Item(category: action.category.rawValue, kind: kind, target: action.target,
                        label: action.label, bytes: action.bytes, error: results?[index].error)
        }
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
