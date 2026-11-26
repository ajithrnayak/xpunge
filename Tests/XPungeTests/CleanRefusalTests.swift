import Testing
@testable import xpunge

@Suite struct CleanRefusalTests {
    @Test func refusesWhileXcodeOrSimulatorRuns() {
        let reason = Clean.refusal(running: ["Xcode", "Simulator"], stdinIsTerminal: true, yes: true)
        #expect(reason?.hasPrefix("Quit Xcode and Simulator first.") == true)
        #expect(reason?.contains("--dry-run") == true)
    }

    @Test func refusesWithoutATerminalUnlessYes() {
        #expect(Clean.refusal(running: [], stdinIsTerminal: false, yes: false)?.hasPrefix("Not a terminal") == true)
        #expect(Clean.refusal(running: [], stdinIsTerminal: false, yes: true) == nil)
    }

    @Test func runningAppsWinOverTheTerminalCheck() {
        let reason = Clean.refusal(running: ["Xcode"], stdinIsTerminal: false, yes: false)
        #expect(reason?.hasPrefix("Quit Xcode first.") == true)
    }

    @Test func allowsACleanFromATerminal() {
        #expect(Clean.refusal(running: [], stdinIsTerminal: true, yes: false) == nil)
    }
}
