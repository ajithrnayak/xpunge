import Foundation
import Testing
@testable import XPungeCore

@Suite struct ScanTests {
    @Test func runtimeSizesComeFromSimctl() throws {
        let home = try TempHome()
        let scanner = Scanner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl()), now: fixtureDate)
        let report = try #require(scanner.scan([.runtimes]).first)
        let bytes = try #require(report.bytes)
        #expect((62_500_000_000...62_700_000_000).contains(bytes))
        #expect(report.details.count == 8)
        #expect(report.note == "8 runtimes, 4 with no recorded use")
        let current = try #require(report.details.first { $0.name.contains("23C54") })
        #expect(current.note?.contains("used by the selected Xcode") == true)
    }

    @Test func xcode27OutputDecodes() throws {
        let home = try TempHome()
        let simctl = SimctlQueries(runner: FakeSimctl(home: home.url, xcode: "xcode27"))
        let runtimes = try simctl.runtimes()
        #expect(runtimes.count == 10)
        #expect(runtimes.allSatisfy { $0.sizeBytes > 0 })
        #expect(simctl.runtimeUsers().byBuild["24B8117"] == [RuntimeUsers.selected])
        let devices = try simctl.devices(in: .standard)
        #expect(devices.count == 118)
        #expect(devices.allSatisfy { !$0.udid.isEmpty && !$0.runtime.isEmpty })
    }

    @Test func scanShowsInstallDateWhenThereIsNoRecordedUse() throws {
        let home = try TempHome()
        let path = "/Library/Developer/CoreSimulator/Images/16863EB6-20F6-43E2-A0D0-3646A507BD42.dmg"
        let fake = FakeSimctl(installDates: [path: fixtureDate.addingTimeInterval(-86_400)])
        let report = try #require(Scanner(env: home.env, simctl: SimctlQueries(runner: fake), now: fixtureDate).scan([.runtimes]).first)
        let runtime = try #require(report.details.first { $0.name.contains("21F79") })
        // The date is shown in local time, so only its month is fixed here.
        let note = try #require(runtime.note)
        #expect(note.hasPrefix("no recorded use, installed 2026-11-1"))
        #expect(note.hasSuffix(", 1 day ago"))
    }

    @Test func runtimesWithoutXcodeAreUnmeasuredNotGuessed() throws {
        let home = try TempHome()
        let report = try #require(Scanner(env: home.env, simctl: nil).scan([.runtimes]).first)
        #expect(report.bytes == nil)
    }

    @Test func derivedDataNotesTheCompilationCache() throws {
        let home = try TempHome()
        try home.file("\(derivedData)/App-abc/x", bytes: 200_000)
        try home.file("\(derivedData)/CompilationCache.noindex/y", bytes: 50_000)
        let report = try #require(Scanner(env: home.env, simctl: nil).scan([.derivedData]).first)
        #expect(report.note?.hasPrefix("includes compilation cache") == true)
        #expect(report.details.first?.name == "App-abc")
        #expect(report.reclaimable == report.bytes)
    }

    @Test func unavailableDevicesAreCountedFromSimctl() throws {
        let home = try TempHome()
        let scanner = Scanner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl(home: home.url)))
        let previews = try #require(scanner.scan([.previews]).first)
        #expect(previews.note == "3 unavailable")
        #expect(previews.details.count == 3)
    }

    @Test func scanOnlyCategoriesHaveNoReclaimableSize() throws {
        let home = try TempHome()
        try home.file("Library/Developer/XCPGDevices/ABC/data/x")
        let report = try #require(Scanner(env: home.env, simctl: nil).scan([.playgroundDevices]).first)
        #expect((report.bytes ?? 0) > 0)
        #expect(report.reclaimable == nil)
    }

    @Test func sizerDoesNotFollowSymlinks() throws {
        let home = try TempHome()
        let big = try home.file("big/file", bytes: 1_000_000)
        let folder = try home.folder("measured")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"),
                                                   withDestinationURL: big.deletingLastPathComponent())
        #expect(Sizer.size(of: folder) < 100_000)
        #expect(Sizer.size(of: home.url.appendingPathComponent("missing")) == 0)
    }

    @Test func locatorSkipsCommandLineToolsAndHonoursDeveloperDir() throws {
        let home = try TempHome()
        let clt = try home.folder("CommandLineTools")
        let fakeXcode = try home.file("Custom.app/Contents/Developer/usr/bin/simctl")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeXcode.path)
        let developer = home.url.appendingPathComponent("Custom.app/Contents/Developer")

        #expect(XcodeLocator.locate(variables: [:], selectedPath: clt.path, applications: home.env.applications) == nil)
        #expect(XcodeLocator.locate(variables: ["DEVELOPER_DIR": developer.path], selectedPath: clt.path,
                                    applications: home.env.applications)?.path == developer.path)
    }

    @Test func scanNamesTheOtherXcodeThatUsesARuntime() throws {
        let home = try TempHome()
        let simctl = SimctlQueries(runner: FakeSimctl(), otherXcodes: [("Xcode-18.4.app", FakeOtherXcode(chosenBuilds: ["22E238"]))])
        let report = try #require(Scanner(env: home.env, simctl: simctl, now: fixtureDate).scan([.runtimes]).first)
        let runtime = try #require(report.details.first { $0.name.contains("22E238") })
        #expect(runtime.note?.hasSuffix("used by Xcode-18.4.app") == true)
    }

    @Test func otherInstalledXcodesExcludeTheSelectedOne() throws {
        let home = try TempHome()
        for name in ["Xcode-26.2.0.app", "Xcode-27.2.0.app"] {
            let simctl = try home.file("Applications/\(name)/Contents/Developer/usr/bin/simctl")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: simctl.path)
        }
        try home.folder("Applications/Xcode-beta.app")  // no simctl: not a usable Xcode
        try home.folder("Applications/Xcodes.app")
        let selected = home.url.appendingPathComponent("Applications/Xcode-27.2.0.app/Contents/Developer")

        let others = XcodeLocator.otherInstalled(applications: home.env.applications, excluding: selected)
        #expect(others.map(\.lastPathComponent) == ["Xcode-26.2.0.app"])
    }

    @Test func defaultPolicyCoversExactlyTheAgreedCategories() {
        let env = Environment(home: URL(fileURLWithPath: "/Users/tester"))
        let byPolicy = Dictionary(grouping: Catalog.categories(in: env), by: \.policy).mapValues { Set($0.map(\.id)) }
        #expect(byPolicy[.namedOnly] == [.runtimes, .deviceSupport, .archives, .xcodesDownloads])
        #expect(byPolicy[.scanOnly] == [.playgroundDevices, .xcodeApps])
        #expect(Set(CategoryID.allCases).count == Catalog.categories(in: env).count)
    }
}
