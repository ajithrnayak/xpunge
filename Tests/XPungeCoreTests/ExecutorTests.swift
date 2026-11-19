import Foundation
import Testing
@testable import XPungeCore

/// These tests really delete, but only inside a fresh temp folder.
@Suite struct ExecutorTests {
    @Test func cleansFixtureTreeAndKeepsEverythingElse() throws {
        let home = try TempHome()
        try home.file("\(derivedData)/App-abc/Build/out.o", bytes: 100_000)
        try home.file("\(derivedData)/CompilationCache.noindex/blob", bytes: 50_000)
        try home.file("Library/Caches/CocoaPods/Pods/x", bytes: 10_000)
        try home.file("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist")
        try home.file("Library/Developer/Xcode/UserData/CodeSnippets/snippet.codesnippet")
        try home.file("Library/Caches/com.apple.Safari/keep")

        let simctl = FakeSimctl()
        let plan = try Planner(env: home.env, simctl: SimctlQueries(runner: simctl)).plan(named: [])
        let results = Executor(env: home.env, simctl: simctl).execute(plan)

        #expect(results.filter { !$0.succeeded }.isEmpty)
        #expect(!home.exists("\(derivedData)/App-abc"))
        #expect(!home.exists("\(derivedData)/CompilationCache.noindex"))
        #expect(!home.exists("Library/Caches/CocoaPods/Pods"))
        // Roots stay; everything outside the plan stays.
        #expect(home.exists(derivedData))
        #expect(home.exists("Library/Caches/CocoaPods"))
        #expect(home.exists("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist"))
        #expect(home.exists("Library/Developer/Xcode/UserData/CodeSnippets/snippet.codesnippet"))
        #expect(home.exists("Library/Caches/com.apple.Safari/keep"))
        // Device clean-up went to (fake) simctl, never to the file system.
        #expect(simctl.destructiveCalls == [["delete", "unavailable"], ["--set", "previews", "delete", "unavailable"]])
    }

    @Test func symlinkInsideRootIsRemovedWithoutTouchingItsTarget() throws {
        let home = try TempHome()
        let precious = try home.file("Documents/precious/file.txt")
        try home.folder(derivedData)
        let link = home.url.appendingPathComponent("\(derivedData)/Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: precious.deletingLastPathComponent())

        let plan = try Planner(env: home.env, simctl: nil).plan(named: [.derivedData])
        #expect(plan.actions.map(\.label) == ["Linked"])
        #expect(plan.actions[0].bytes == 0)  // sizes never follow links
        let results = Executor(env: home.env, simctl: nil).execute(plan)

        #expect(results.filter { !$0.succeeded }.isEmpty)
        #expect(home.exists("Documents/precious/file.txt"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
    }

    @Test func executorRechecksTheGuard() throws {
        let home = try TempHome()
        let victim = try home.file("Documents/thesis.pages")
        var forged = Plan()
        forged.actions = [Action(category: .derivedData, kind: .remove(victim), label: "thesis", bytes: 0)]

        let remover = RecordingRemover()
        let results = Executor(env: home.env, remover: remover, simctl: nil).execute(forged)

        #expect(results.count == 1 && !results[0].succeeded)
        #expect(remover.removed.isEmpty)
        #expect(home.exists("Documents/thesis.pages"))
    }

    @Test func forgedSimctlAllIsNeverRun() throws {
        let home = try TempHome()
        let simctl = FakeSimctl()
        var forged = Plan()
        forged.actions = [Action(category: .runtimes, kind: .simctl(["runtime", "delete", "all"]), label: "all", bytes: 0)]
        let results = Executor(env: home.env, simctl: simctl).execute(forged)
        #expect(!results[0].succeeded)
        #expect(simctl.calls.isEmpty)
    }

    @Test func alreadyGoneCountsAsDone() throws {
        let home = try TempHome()
        let item = try home.folder("\(derivedData)/App-abc")
        let plan = try Planner(env: home.env, simctl: nil).plan(named: [.derivedData])
        try FileManager.default.removeItem(at: item)
        let results = Executor(env: home.env, simctl: nil).execute(plan)
        #expect(results.filter { !$0.succeeded }.isEmpty)
    }

    @Test func runtimeDeletionGoesOneUUIDAtATime() throws {
        let home = try TempHome()
        let simctl = FakeSimctl()
        let plan = try Planner(env: home.env, simctl: SimctlQueries(runner: simctl))
            .plan(named: [.runtimes], options: CleanOptions(runtimes: ["21A328", "21A342"]))
        _ = Executor(env: home.env, simctl: simctl).execute(plan)
        #expect(simctl.destructiveCalls == [
            ["runtime", "delete", "178757CA-BA71-44B0-BDFD-C7BB36335306"],
            ["runtime", "delete", "6BE7E692-17E8-4DA1-A8C2-20795CF79BBE"],
        ])
    }
}
