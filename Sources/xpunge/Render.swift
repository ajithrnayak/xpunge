import Foundation
import XPungeCore

enum Render {
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: scan

    static func scanTable(_ reports: [CategoryReport], details: Bool, xcodeFound: Bool) -> String {
        var rows: [[String]] = [["CATEGORY", "SIZE", "CLEAN", "NOTE"]]
        var detailLines: [String: [String]] = [:]

        for report in reports {
            var note = report.note ?? ""
            if case .some(let reclaimable) = report.reclaimable,
               report.id == .simulatorDevices || report.id == .previews || report.id == .testDevices,
               reclaimable > 0 {
                note += " (\(ByteFormat.string(reclaimable)))"
            }
            rows.append([report.id.rawValue, report.bytes.map(ByteFormat.string) ?? "-", policyLabel(report), note])
            if details {
                detailLines[report.id.rawValue] = report.details.map { detail in
                    let size = ByteFormat.string(detail.bytes).leftPadded(to: 10)
                    return "    \(size)  \(detail.name)" + (detail.note.map { "  (\($0))" } ?? "")
                }
            }
        }

        var lines = table(rows) { row in detailLines[row[0]] ?? [] }

        let defaultTotal = reports.filter { $0.policy == .byDefault }.compactMap(\.reclaimable).reduce(0, +)
        let named = reports.filter { $0.policy == .namedOnly && ($0.bytes ?? 0) > 0 }
        lines.append("")
        lines.append("A plain `xpunge clean` would free about \(ByteFormat.string(defaultTotal)). Preview it with `xpunge clean --dry-run`.")
        if !named.isEmpty {
            let list = named.map { "\($0.id.rawValue) \(ByteFormat.string($0.bytes ?? 0))" }.joined(separator: ", ")
            lines.append("Cleaned only when named: \(list).")
        }
        if !xcodeFound {
            lines.append("No full Xcode found, so runtimes and device sets are partly unmeasured. Set DEVELOPER_DIR to an Xcode's Contents/Developer.")
        }
        return lines.joined(separator: "\n")
    }

    private static func policyLabel(_ report: CategoryReport) -> String {
        switch report.policy {
        case .byDefault: "default"
        case .namedOnly: "by name"
        case .scanOnly: "report only"
        }
    }

    // MARK: clean

    static func plan(_ plan: Plan, dryRun: Bool) -> String {
        var lines: [String] = []
        if plan.actions.isEmpty {
            lines.append("Nothing to clean.")
        } else {
            let header = dryRun ? "Dry run: would remove" : "Plan: remove"
            lines.append("\(header) \(plan.actions.count) item(s), \(ByteFormat.string(plan.totalBytes)).")
            for category in plan.categories {
                let actions = plan.actions.filter { $0.category == category }
                let total = actions.reduce(0) { $0 + $1.bytes }
                lines.append("")
                lines.append("\(category.rawValue)  \(ByteFormat.string(total))")
                for action in actions.sorted(by: { $0.bytes > $1.bytes }) {
                    lines.append("  \(ByteFormat.string(action.bytes).leftPadded(to: 10))  \(action.label)")
                    if case .simctl = action.kind { lines.append("              runs: \(action.target)") }
                }
            }
        }
        if !plan.notes.isEmpty {
            lines.append("")
            lines += plan.notes.map { "Note: \($0)" }
        }
        if dryRun && !plan.actions.isEmpty {
            lines.append("")
            lines.append("Nothing was removed. Run without --dry-run to clean.")
        }
        return lines.joined(separator: "\n")
    }

    static func progress(_ result: ActionResult) -> String {
        let size = ByteFormat.string(result.action.bytes).leftPadded(to: 10)
        if let error = result.error {
            return "  failed  \(size)  \(result.action.label): \(error)"
        }
        return "  done    \(size)  \(result.action.label)"
    }

    static func summary(_ results: [ActionResult]) -> String {
        let done = results.filter(\.succeeded)
        let freed = done.reduce(0) { $0 + $1.action.bytes }
        var line = "\nFreed about \(ByteFormat.string(freed)) (\(done.count) of \(results.count) item(s))."
        let failed = results.count - done.count
        if failed > 0 { line += " \(failed) failed; see above." }
        return line
    }

    // MARK: table helper

    private static func table(_ rows: [[String]], after: ([String]) -> [String]) -> [String] {
        let widths = (0..<rows[0].count).map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.enumerated().flatMap { index, row -> [String] in
            let cells = row.enumerated().map { column, cell -> String in
                if column == 1 { return cell.leftPadded(to: widths[column]) }
                return column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            let line = cells.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
            return [line] + (index == 0 ? [] : after(row))
        }
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
