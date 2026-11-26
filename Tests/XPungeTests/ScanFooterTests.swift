import Foundation
import Testing
@testable import xpunge
@testable import XPungeCore

@Suite struct ScanFooterTests {
    let plain = Terminal(color: false, width: nil, playful: false)

    func report(_ id: CategoryID, _ policy: Policy, bytes: Int64, reclaimable: Int64?) -> CategoryReport {
        CategoryReport(id: id, title: id.rawValue, policy: policy, bytes: bytes, reclaimable: reclaimable, note: nil, details: [])
    }

    func footer(_ reports: [CategoryReport], complete: Bool = true) -> String {
        Render.scanTable(reports, details: false, complete: complete, xcodeFound: true, terminal: plain)
    }

    @Test func suggestsADryRunWhenTheDefaultSetHasSomethingToClean() {
        let text = footer([
            report(.derivedData, .byDefault, bytes: 2_000_000_000, reclaimable: 2_000_000_000),
            report(.runtimes, .namedOnly, bytes: 8_000_000_000, reclaimable: nil),
        ])
        #expect(text.contains("a plain clean frees about 2 GB"))
        #expect(text.contains("Preview a clean with `xpunge clean --dry-run`."))
    }

    @Test func saysNothingIsLeftInsteadOfSuggestingADryRun() {
        let text = footer([
            report(.derivedData, .byDefault, bytes: 0, reclaimable: 0),
            report(.runtimes, .namedOnly, bytes: 25_000_000_000, reclaimable: nil),
            report(.xcodesDownloads, .namedOnly, bytes: 3_400_000_000, reclaimable: 3_400_000_000),
        ])
        #expect(!text.contains("frees about 0 B"))
        #expect(!text.contains("clean --dry-run"))
        #expect(text.contains("Xcode is using 28.4 GB here; nothing left to clean by default."))
        #expect(text.contains("See what's in them with `xpunge scan simulator-runtimes xcodes-downloads --details`."))
    }

    @Test func scanOfNamedCategoriesOnlyDoesNotTalkAboutAPlainClean() {
        let text = footer([report(.runtimes, .namedOnly, bytes: 25_000_000_000, reclaimable: nil)], complete: false)
        #expect(!text.contains("plain clean"))
        #expect(!text.contains("nothing left"))
        #expect(text.contains("These categories use 25 GB."))
    }

    @Test func allCleanAndNothingNamedEndsQuietly() {
        let text = footer([report(.derivedData, .byDefault, bytes: 0, reclaimable: 0)])
        #expect(text.hasSuffix("Xcode is using 0 B here; nothing left to clean by default."))
    }
}
