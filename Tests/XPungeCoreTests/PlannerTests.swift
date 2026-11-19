import Foundation
import Testing
@testable import XPungeCore

@Suite struct PlannerTests {
    @Test func defaultSetLeavesNamedOnlyCategoriesAlone() throws {
        let home = try TempHome()
        try home.file("\(derivedData)/App-abc/Build/out.o")
        try home.file("Library/Caches/org.swift.swiftpm/repositories/pkg/data")
        try home.file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist")
        try home.file("Library/Developer/Xcode/iOS DeviceSupport/16.6 (20F75) arm64e/Symbols/x")
        try home.file("Library/Application Support/com.robotsandpencils.XcodesApp/Xcode-15.xip")

        let plan = try Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl())).plan(named: [])

        #expect(Set(plan.categories) == [.derivedData, .swiftpmCache, .simulatorDevices, .previews])
        #expect(!plan.categories.contains(.archives))
        #expect(!plan.categories.contains(.deviceSupport))
        #expect(!plan.categories.contains(.xcodesDownloads))
        #expect(!plan.categories.contains(.runtimes))
    }

    @Test func defaultSetDeletesOnlyUnavailableDevicesThroughSimctl() throws {
        let home = try TempHome()
        let plan = try Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl())).plan(named: [])
        let commands = plan.actions.compactMap { action -> [String]? in
            if case .simctl(let args) = action.kind { return args }
            return nil
        }
        // The testing set fixture has no unavailable devices, so no command for it.
        #expect(commands == [["delete", "unavailable"], ["--set", "previews", "delete", "unavailable"]])
    }

    @Test func removesContentsButKeepsRoots() throws {
        let home = try TempHome()
        try home.file("\(derivedData)/App-abc/x")
        try home.file("\(derivedData)/CompilationCache.noindex/y")
        let plan = try Planner(env: home.env, simctl: nil).plan(named: [.derivedData])
        let paths = plan.actions.compactMap { action -> String? in
            if case .remove(let url) = action.kind { return url.lastPathComponent }
            return nil
        }
        #expect(Set(paths) == ["App-abc", "CompilationCache.noindex"])
    }

    @Test func withoutXcodeDeviceCategoriesAreSkippedWithANote() throws {
        let home = try TempHome()
        let plan = try Planner(env: home.env, simctl: nil).plan(named: [])
        #expect(!plan.actions.contains { if case .simctl = $0.kind { true } else { false } })
        #expect(plan.notes.contains { $0.contains("simulator-devices") })
    }

    @Test func runtimesNeedASelector() throws {
        let home = try TempHome()
        let planner = Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl()))
        #expect(throws: PlanError.runtimesNeedSelector) { try planner.plan(named: [.runtimes]) }
        #expect(throws: PlanError.runtimeOptionsWithoutCategory) {
            try planner.plan(named: [], options: CleanOptions(notUsedSinceDays: 30))
        }
        #expect(throws: PlanError.unknownRuntime("99Z999")) {
            try planner.plan(named: [.runtimes], options: CleanOptions(runtimes: ["99Z999"]))
        }
    }

    @Test func notUsedSinceKeepsTheSelectedXcodesRuntime() throws {
        let home = try TempHome()
        let planner = Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl()))
        let plan = try planner.plan(named: [.runtimes], options: CleanOptions(notUsedSinceDays: 365, now: fixtureDate))

        let builds = Set(plan.actions.map { $0.label.components(separatedBy: "(").last!.dropLast() }.map(String.init))
        #expect(builds == ["21A328", "21A342", "21C62", "21E213", "21F79", "22D8075", "22E238"])
        #expect(!builds.contains("23C54"))
        #expect(plan.notes.contains { $0.contains("23C54") })
        for action in plan.actions {
            guard case .simctl(let args) = action.kind else { Issue.record("expected simctl"); continue }
            #expect(args.count == 3 && args[0] == "runtime" && args[1] == "delete")
            #expect(UUID(uuidString: args[2]) != nil)
        }
    }

    @Test func runtimeByBuildResolvesToItsUUID() throws {
        let home = try TempHome()
        let planner = Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl()))
        let plan = try planner.plan(named: [.runtimes], options: CleanOptions(runtimes: ["21A328"]))
        #expect(plan.actions.count == 1)
        #expect(plan.actions[0].kind == .simctl(["runtime", "delete", "178757CA-BA71-44B0-BDFD-C7BB36335306"]))
        #expect(plan.actions[0].bytes == 7_559_529_352)
    }

    @Test func neverPassesAllToSimctl() throws {
        let home = try TempHome()
        let planner = Planner(env: home.env, simctl: SimctlQueries(runner: FakeSimctl()))
        let plans = [
            try planner.plan(named: []),
            try planner.plan(named: [.runtimes], options: CleanOptions(notUsedSinceDays: 0, now: fixtureDate)),
            try planner.plan(named: [.runtimes, .simulatorDevices, .previews, .testDevices],
                             options: CleanOptions(runtimes: ["23C54"])),
        ]
        for action in plans.flatMap(\.actions) {
            if case .simctl(let args) = action.kind {
                #expect(!args.contains { $0.lowercased() == "all" })
            }
        }
        // Explicitly asking for "all" is not a runtime name.
        #expect(throws: PlanError.unknownRuntime("all")) {
            try planner.plan(named: [.runtimes], options: CleanOptions(runtimes: ["all"]))
        }
    }

    @Test func scanOnlyCategoriesCannotBeCleaned() throws {
        let home = try TempHome()
        let planner = Planner(env: home.env, simctl: nil)
        #expect(throws: PlanError.scanOnly(.playgroundDevices)) { try planner.plan(named: [.playgroundDevices]) }
        #expect(throws: PlanError.scanOnly(.xcodeApps)) { try planner.plan(named: [.xcodeApps]) }
    }

    @Test func xcodesDownloadsTakeOnlyXipFiles() throws {
        let home = try TempHome()
        let dir = "Library/Application Support/com.robotsandpencils.XcodesApp"
        try home.file("\(dir)/Xcode-15.0.0-Beta.5+15A5209g.xip")
        try home.file("\(dir)/Xcode-15.0.0-Beta.5+15A5209g.xip.aria2")
        try home.file("\(dir)/available-xcodes.json")
        try home.folder("\(dir)/something.xip")  // a folder, not a file
        let plan = try Planner(env: home.env, simctl: nil).plan(named: [.xcodesDownloads])
        #expect(Set(plan.actions.map(\.label)) == ["Xcode-15.0.0-Beta.5+15A5209g.xip", "Xcode-15.0.0-Beta.5+15A5209g.xip.aria2"])
    }

    @Test func keepLatestKeepsNewestVersionsPerPlatform() throws {
        let home = try TempHome()
        let ios = "Library/Developer/Xcode/iOS DeviceSupport"
        for name in ["iPhone13,2 16.7 (20H19)", "iPhone13,2 16.5.1 (20F75)", "iPhone13,2 16.5 (20F66)",
                     "16.6 (20F75) arm64e", "16.5.1 (20F66) arm64e"] {
            try home.file("\(ios)/\(name)/Info.plist")
        }
        try home.file("Library/Developer/Xcode/watchOS DeviceSupport/Watch3,2 8.7.1 (19U67)/Info.plist")

        let plan = try Planner(env: home.env, simctl: nil)
            .plan(named: [.deviceSupport], options: CleanOptions(keepLatest: 2))
        // Kept: 16.7 and 16.6 on iOS, 8.7.1 on watchOS. Both 16.5.1 entries and 16.5 go.
        #expect(Set(plan.actions.map(\.label)) == ["iPhone13,2 16.5.1 (20F75)", "iPhone13,2 16.5 (20F66)", "16.5.1 (20F66) arm64e"])
    }

    @Test func deviceSupportVersionParsing() {
        #expect(DeviceSupport.version(of: "16.6 (20F75) arm64e") == [16, 6])
        #expect(DeviceSupport.version(of: "iPhone13,2 16.5.1 (20F75)") == [16, 5, 1])
        #expect(DeviceSupport.version(of: "Watch3,2 8.7.1 (19U67)") == [8, 7, 1])
        #expect(DeviceSupport.version(of: ".DS_Store") == nil)
    }

    @Test func archivesWarnAboutDSYMs() throws {
        let home = try TempHome()
        try home.file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist")
        let plan = try Planner(env: home.env, simctl: nil).plan(named: [.archives])
        #expect(plan.actions.map(\.label) == ["2026-01-01"])
        #expect(plan.notes.contains { $0.contains("dSYM") })
    }
}
