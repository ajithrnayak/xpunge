import ArgumentParser
import Foundation
import XPungeCore

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show how much space each Xcode category uses, largest first. Read-only."
    )

    @Argument(help: "Categories to scan (default: all). One of: \(CategoryID.allCases.map(\.rawValue).joined(separator: ", ")).")
    var categories: [CategoryID] = []

    @Flag(help: "List the items inside each category.")
    var details = false

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func run() throws {
        noteRenamedCategories()
        let context = Context.current()
        let scanner = Scanner(env: context.env, simctl: context.queries)
        let reports = scanner.scan(categories.isEmpty ? CategoryID.allCases : categories)

        if json {
            print(try Render.json(reports))
        } else {
            print(Render.scanTable(reports, details: details, complete: categories.isEmpty,
                                   xcodeFound: context.simctl != nil,
                                   terminal: Terminal.current()))
        }
    }
}
