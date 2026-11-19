import Foundation

/// A boxed plain-text table:
///
///     +----------+---------+
///     |     xpunge scan    |
///     +----------+---------+
///     | Category |    Size |
///     +----------+---------+
///     | archives |  1.2 GB |
///     +----------+---------+
public struct TextTable: Sendable {
    public enum Alignment: Sendable { case left, right }

    public struct Column: Sendable {
        public let title: String
        public let alignment: Alignment
        /// Shortened with "…" first when the table is wider than the terminal.
        public let flexible: Bool

        public init(_ title: String, _ alignment: Alignment = .left, flexible: Bool = false) {
            self.title = title
            self.alignment = alignment
            self.flexible = flexible
        }
    }

    public enum Row: Sendable {
        case cells([String], RowStyle = .normal)
        case separator
    }

    public enum RowStyle: Sendable { case normal, dim, bold, good, bad }

    public var title: String?
    public var columns: [Column]
    public var rows: [Row] = []

    public init(title: String? = nil, columns: [Column]) {
        self.title = title
        self.columns = columns
    }

    public mutating func add(_ cells: [String], _ style: RowStyle = .normal) {
        rows.append(.cells(cells, style))
    }

    public mutating func addSeparator() {
        if case .separator = rows.last { return }
        rows.append(.separator)
    }

    /// - Parameters:
    ///   - maxWidth: terminal width; flexible columns shrink to fit it.
    ///   - color: wrap the title, header and styled rows in ANSI colors.
    public func render(maxWidth: Int? = nil, color: Bool = false) -> String {
        var widths = columns.map { $0.title.count }
        for case .cells(let cells, _) in rows {
            for (index, cell) in cells.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        if let title {
            // Widen the last column if the title needs more room than the columns give it.
            let inner = widths.reduce(0, +) + 3 * (widths.count - 1)
            if title.count > inner { widths[widths.count - 1] += title.count - inner }
        }
        if let maxWidth { shrink(&widths, toFit: maxWidth) }

        let border = "+" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+") + "+"
        let innerWidth = border.count - 4
        var lines = [border]

        if let title {
            let text = Self.truncate(title, to: innerWidth)
            let left = (innerWidth - text.count) / 2
            let padded = String(repeating: " ", count: left) + text
                + String(repeating: " ", count: innerWidth - left - text.count)
            lines.append("| " + Self.paint(padded, .good, color, bold: true) + " |")
            lines.append(border)
        }

        lines.append(line(columns.map(\.title), widths: widths, style: .bold, color: color))
        lines.append(border)
        for row in rows {
            switch row {
            case .separator: lines.append(border)
            case .cells(let cells, let style): lines.append(line(cells, widths: widths, style: style, color: color))
            }
        }
        if lines.last != border { lines.append(border) }
        return lines.joined(separator: "\n")
    }

    private func line(_ cells: [String], widths: [Int], style: RowStyle, color: Bool) -> String {
        let parts = widths.indices.map { index -> String in
            let text = Self.truncate(index < cells.count ? cells[index] : "", to: widths[index])
            let padding = String(repeating: " ", count: widths[index] - text.count)
            let cell = columns[index].alignment == .right ? padding + text : text + padding
            return Self.paint(cell, style, color, bold: style == .bold)
        }
        return "| " + parts.joined(separator: " | ") + " |"
    }

    private func shrink(_ widths: inout [Int], toFit maxWidth: Int) {
        let flexible = columns.indices.filter { columns[$0].flexible }
        while widths.reduce(0, +) + 3 * widths.count + 1 > maxWidth {
            guard let widest = flexible.max(by: { widths[$0] < widths[$1] }), widths[widest] > 12 else { return }
            widths[widest] -= 1
        }
    }

    static func truncate(_ text: String, to width: Int) -> String {
        guard text.count > width else { return text }
        guard width > 1 else { return String(text.prefix(width)) }
        return String(text.prefix(width - 1)) + "…"
    }

    static func paint(_ text: String, _ style: RowStyle, _ color: Bool, bold: Bool) -> String {
        guard color else { return text }
        let code: String
        switch style {
        case .normal: return text
        case .bold: code = "1"
        case .dim: code = "2"
        case .good: code = bold ? "1;32" : "32"
        case .bad: code = "31"
        }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}
