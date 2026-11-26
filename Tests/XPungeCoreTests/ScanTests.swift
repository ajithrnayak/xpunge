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
        #expect(report.note == "8 runtimes, 1 used by Xcode, 3 with no recorded use")
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

    @Test func runtimesCategoryUsesApplesNameAndKeepsTheOldOne() {
        #expect(CategoryID.runtimes.rawValue == "simulator-runtimes")
        #expect(CategoryID(name: "simulator-runtimes") == .runtimes)
        #expect(CategoryID(name: "runtimes") == .runtimes)
        #expect(CategoryID(name: "runtime") == nil)
        #expect(CategoryID(rawValue: "runtimes") == nil)  // JSON and help only ever use the new name
        #expect(CategoryID.aliases.values.allSatisfy { CategoryID.allCases.contains($0) })
    }

    @Test func runtimesNoteDoesNotCallUsedRuntimesUnused() throws {
        let home = try TempHome()
        // 23C54 (selected Xcode) and 22D8075 (another Xcode) have no recorded use, but Xcode uses them.
        let simctl = SimctlQueries(runner: FakeSimctl(), otherXcodes: [("Xcode-18.3.app", FakeOtherXcode(chosenBuilds: ["22D8075"]))])
        let report = try #require(Scanner(env: home.env, simctl: simctl, now: fixtureDate).scan([.runtimes]).first)
        #expect(report.note == "8 runtimes, 2 used by Xcode, 2 with no recorded use")
    }

    @Test func runtimeNoXcodeUsesIsPointedAtTheBuildXcodeUses() throws {
        let home = try TempHome()
        // Captured on a Mac with two iOS 27.2 builds; Xcode 27.2 uses 24B8117.
        let simctl = SimctlQueries(runner: FakeSimctl(home: home.url, xcode: "xcode27"))
        let report = try #require(Scanner(env: home.env, simctl: simctl, now: fixtureDate).scan([.runtimes]).first)
        let twins = report.details.filter { $0.name.hasPrefix("iOS 27.2 Simulator") }
        #expect(twins.count == 2)
        let unused = try #require(twins.first { !$0.name.contains("24B8117") })
        #expect(unused.note?.hasSuffix("no Xcode uses this build; Xcode uses 24B8117") == true)
        let used = try #require(twins.first { $0.name.contains("24B8117") })
        #expect(used.note?.contains("no Xcode uses this build") == false)
    }

    @Test func runtimeSizeIncludesItsDyldCacheForThisMacOSBuild() throws {
        let home = try TempHome()  // macOS build 26B131
        let current = "SystemDyld/26B131/com.apple.CoreSimulator.SimRuntime.iOS-17-0.21A328"
        try home.file("\(current)/dyld_sim_shared_cache_arm64e", bytes: 3_000_000)
        // Left from an older macOS build: not seen to go with the runtime, so not promised.
        try home.file("SystemDyld/25C56/com.apple.CoreSimulator.SimRuntime.iOS-17-0.21A328/dyld_sim_shared_cache_arm64e", bytes: 1_000_000)
        // iOS 17.0.1 (21A342) shares the identifier but not the build.
        try home.file("SystemDyld/26B131/com.apple.CoreSimulator.SimRuntime.iOS-99-0.99Z99/dyld_sim_shared_cache_arm64e", bytes: 5_000_000)
        let dyld = Sizer.size(of: home.url.appendingPathComponent(current))
        #expect(dyld >= 3_000_000)

        let simctl = SimctlQueries(runner: FakeSimctl())
        let report = try #require(Scanner(env: home.env, simctl: simctl, now: fixtureDate).scan([.runtimes]).first)
        let ios17 = try #require(report.details.first { $0.name.contains("21A328") })
        #expect(ios17.bytes == 7_559_529_352 + dyld)
        #expect(ios17.note?.contains("includes \(ByteFormat.string(dyld)) dyld cache") == true)
        let ios1701 = try #require(report.details.first { $0.name.contains("21A342") })
        #expect(ios1701.bytes == 7_210_691_623)
        #expect(ios1701.note?.contains("dyld") == false)

        let plan = try Planner(env: home.env, simctl: simctl).plan(named: [.runtimes], options: CleanOptions(runtimes: ["21A328"]))
        #expect(plan.actions.map(\.bytes) == [7_559_529_352 + dyld])
        #expect(plan.actions.first?.note == "includes \(ByteFormat.string(dyld)) dyld cache")
    }

    @Test func runtimeSizeLeavesOutDyldCacheWhenMacOSBuildIsUnknown() throws {
        let home = try TempHome()
        try home.file("SystemDyld/26B131/com.apple.CoreSimulator.SimRuntime.iOS-17-0.21A328/dyld_sim_shared_cache_arm64e", bytes: 3_000_000)
        var env = home.env
        env.macOSBuild = nil
        let report = try #require(Scanner(env: env, simctl: SimctlQueries(runner: FakeSimctl()), now: fixtureDate).scan([.runtimes]).first)
        #expect(report.details.first { $0.name.contains("21A328") }?.bytes == 7_559_529_352)
    }

    @Test func runtimeLabelsMatchXcodeComponents() throws {
        let runtimes = try SimctlQueries(runner: FakeSimctl()).runtimes()
        let ios17 = try #require(runtimes.first { $0.build == "21A328" })
        #expect(ios17.label == "iOS 17.0 Simulator (21A328)")
    }

    @Test func defaultPolicyCoversExactlyTheAgreedCategories() {
        let env = Environment(home: URL(fileURLWithPath: "/Users/tester"))
        let byPolicy = Dictionary(grouping: Catalog.categories(in: env), by: \.policy).mapValues { Set($0.map(\.id)) }
        #expect(byPolicy[.namedOnly] == [.runtimes, .deviceSupport, .archives, .xcodesDownloads])
        #expect(byPolicy[.scanOnly] == [.playgroundDevices, .xcodeApps])
        #expect(Set(CategoryID.allCases).count == Catalog.categories(in: env).count)
    }
}
