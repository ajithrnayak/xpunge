import ArgumentParser
import Foundation
import XPungeCore

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove what scan found. Shows the plan and asks before removing anything.",
        discussion: """
        With no categories, cleans the safe default set: caches, DerivedData, documentation, and
        unavailable simulator, Previews and test devices. Removal is permanent.

        Examples:
          xpunge clean --dry-run
          xpunge clean derived-data swiftpm-cache
          xpunge clean simulator-runtimes --not-used-since 180
          xpunge clean simulator-runtimes --runtime 21A328
          xpunge clean device-support --keep-latest 2
        """
    )

    @Argument(help: "Categories to clean (default: the safe default set).")
    var categories: [CategoryID] = []

    @Flag(name: [.short, .long], help: "Show what would be removed, and remove nothing.")
    var dryRun = false

    @Flag(name: [.short, .long], help: "Don't ask for confirmation.")
    var yes = false

    @Flag(help: "Print JSON. Needs --dry-run or --yes.")
    var json = false

    @Option(name: .customLong("runtime"), help: "Simulator runtime build or UUID to delete (repeatable). Needs the simulator-runtimes category.")
    var runtimes: [String] = []

    @Option(help: "Delete simulator runtimes with no use in this many days. Runtimes with no recorded use count as unused; runtimes an installed Xcode uses are kept.")
    var notUsedSince: Int?

    @Option(help: "Keep this many newest versions in each DeviceSupport folder.")
    var keepLatest: Int?

    func validate() throws {
        if json && !dryRun && !yes {
            throw ValidationError("--json needs --dry-run or --yes, so no prompt mixes with the JSON.")
        }
    }

    func run() throws {
        noteRenamedCategories()
        let context = Context.current()
        let options = CleanOptions(runtimes: runtimes, notUsedSinceDays: notUsedSince, keepLatest: keepLatest)

        var plan: Plan
        do {
            plan = try Planner(env: context.env, simctl: context.queries).plan(named: categories, options: options)
        } catch let error as GuardError {
            printError(error.description)
            throw Exit.refused
        } catch let error as PlanError {
            printError(error.description)
            throw ExitCode.failure
        }

        plan = plan.ordered()
        let terminal = Terminal.current()

        if dryRun {
            print(json ? try Render.json(PlanOutput(plan: plan, dryRun: true, results: nil))
                       : Render.plan(plan, dryRun: true, terminal: terminal))
            return
        }
        if !json { print(Render.plan(plan, dryRun: false, terminal: terminal)) }
        guard !plan.actions.isEmpty else { return }

        let running = RunningApps.running()
        guard running.isEmpty else {
            printError("Quit \(running.joined(separator: " and ")) first. Cleaning while they run can corrupt their state.")
            throw Exit.refused
        }

        if !yes {
            guard isatty(STDIN_FILENO) == 1 else {
                printError("Not a terminal, so I can't ask for confirmation. Use --yes, or --dry-run to preview.")
                throw Exit.refused
            }
            print("Remove \(plan.actions.count) item(s), \(ByteFormat.string(plan.totalBytes))? This cannot be undone. [y/N] ", terminator: "")
            guard let answer = readLine(), ["y", "yes"].contains(answer.lowercased()) else {
                print("Nothing removed.")
                return
            }
        }

        let executor = Executor(env: context.env, simctl: context.simctl)
        let results = executor.execute(plan) { result in
            if !json { print(Render.progress(result, terminal: terminal)) }
        }

        if json {
            print(try Render.json(PlanOutput(plan: plan, dryRun: false, results: results)))
        } else {
            print(Render.summary(results, terminal: terminal))
        }
        if results.contains(where: { !$0.succeeded }) { throw Exit.partial }
    }
}
