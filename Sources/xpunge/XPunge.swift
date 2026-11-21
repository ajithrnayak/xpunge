import ArgumentParser
import Foundation
import XPungeCore

@main
struct XPunge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xpunge",
        abstract: "See how much disk space Xcode uses, and reclaim it safely.",
        discussion: """
        Start with `xpunge scan`, then preview with `xpunge clean --dry-run`.
        Archives, device support, runtimes and Xcodes downloads are only cleaned when named.
        """,
        version: "0.1.1",
        subcommands: [Scan.self, Clean.self],
        defaultSubcommand: Scan.self
    )
}

extension CategoryID: ExpressibleByArgument {}

/// The real environment plus a simctl runner, if a full Xcode can be found.
struct Context {
    let env: Environment
    let simctl: Simctl?
    /// Other installed Xcode apps, whose runtimes are protected too.
    let otherXcodes: [URL]
    var queries: SimctlQueries? {
        simctl.map { selected in
            SimctlQueries(runner: selected, otherXcodes: otherXcodes.map { app in
                (app.lastPathComponent, Simctl(developerDir: app.appendingPathComponent("Contents/Developer", isDirectory: true)))
            })
        }
    }

    static func current() -> Context {
        let env = Environment.current()
        let developerDir = XcodeLocator.locate(
            variables: env.variables,
            selectedPath: XcodeLocator.xcodeSelectPath(),
            applications: env.applications
        )
        return Context(
            env: env, simctl: developerDir.map(Simctl.init(developerDir:)),
            otherXcodes: XcodeLocator.otherInstalled(applications: env.applications, excluding: developerDir)
        )
    }
}

enum Exit {
    static let partial = ExitCode(2)
    static let refused = ExitCode(3)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data(("xpunge: " + message + "\n").utf8))
}
