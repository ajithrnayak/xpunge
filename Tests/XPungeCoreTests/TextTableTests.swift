import Testing
@testable import XPungeCore

@Suite struct TextTableTests {
    @Test func rendersBoxedTableWithTitle() {
        var table = TextTable(title: "xpunge scan", columns: [.init("Category"), .init("Size", .right)])
        table.add(["archives", "1.2 GB"])
        table.add(["derived-data", "187 MB"])
        table.addSeparator()
        table.add(["Total", "1.39 GB"])

        #expect(table.render() == """
        +--------------+---------+
        |      xpunge scan       |
        +--------------+---------+
        | Category     |    Size |
        +--------------+---------+
        | archives     |  1.2 GB |
        | derived-data |  187 MB |
        +--------------+---------+
        | Total        | 1.39 GB |
        +--------------+---------+
        """)
    }

    @Test func everyLineHasTheSameWidth() {
        var table = TextTable(title: "a title much wider than the columns", columns: [.init("A"), .init("B")])
        table.add(["x", "y"])
        let widths = Set(table.render().split(separator: "\n").map(\.count))
        #expect(widths.count == 1)
    }

    @Test func flexibleColumnShrinksToFitWithEllipsis() {
        var table = TextTable(columns: [.init("Item", flexible: true), .init("Size", .right)])
        table.add([String(repeating: "x", count: 80), "1 GB"])
        let lines = table.render(maxWidth: 40).split(separator: "\n")
        #expect(lines.allSatisfy { $0.count <= 40 })
        #expect(lines.contains { $0.contains("…") })
    }

    @Test func noColorCodesUnlessAsked() {
        var table = TextTable(title: "t", columns: [.init("A")])
        table.add(["x"], .bad)
        #expect(!table.render().contains("\u{1B}["))
        #expect(table.render(color: true).contains("\u{1B}[31m"))
    }

    @Test func doubleSeparatorsCollapse() {
        var table = TextTable(columns: [.init("A")])
        table.add(["x"])
        table.addSeparator()
        table.addSeparator()
        #expect(table.rows.count == 2)
    }
}
