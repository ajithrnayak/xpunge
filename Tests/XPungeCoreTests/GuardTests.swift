import Foundation
import Testing
@testable import XPungeCore

@Suite struct GuardTests {
    private func category(_ id: CategoryID, in env: Environment) -> XPungeCore.Category {
        Catalog.categories(in: env).first { $0.id == id }!
    }

    private func remove(_ url: URL, _ id: CategoryID = .derivedData) -> Action {
        Action(category: id, kind: .remove(url), label: url.lastPathComponent, bytes: 0)
    }

    @Test func allowsDirectChildOfRoot() throws {
        let home = try TempHome()
        let item = try home.folder("\(derivedData)/App-abc")
        try Guard.check(remove(item), category: category(.derivedData, in: home.env), home: home.url)
    }

    @Test func refusesTheRootItself() throws {
        let home = try TempHome()
        let root = try home.folder(derivedData)
        #expect(throws: GuardError.self) {
            try Guard.check(remove(root), category: category(.derivedData, in: home.env), home: home.url)
        }
    }

    @Test func refusesGrandchildrenAndOtherFolders() throws {
        let home = try TempHome()
        let deep = try home.folder("\(derivedData)/App-abc/Build")
        let documents = try home.file("Documents/thesis.pages")
        let cat = category(.derivedData, in: home.env)
        #expect(throws: GuardError.self) { try Guard.check(remove(deep), category: cat, home: home.url) }
        #expect(throws: GuardError.self) { try Guard.check(remove(documents), category: cat, home: home.url) }
    }

    @Test func refusesPathTraversal() throws {
        let home = try TempHome()
        try home.file("Documents/thesis.pages")
        let sneaky = home.url.appendingPathComponent("\(derivedData)/../../../../Documents")
        #expect(throws: GuardError.self) {
            try Guard.check(remove(sneaky), category: category(.derivedData, in: home.env), home: home.url)
        }
    }

    @Test func refusesActionFromTheWrongCategory() throws {
        let home = try TempHome()
        let archive = try home.folder("Library/Developer/Xcode/Archives/2026-01-01")
        #expect(throws: GuardError.self) {
            try Guard.check(remove(archive, .derivedData), category: category(.archives, in: home.env), home: home.url)
        }
    }

    @Test func refusesProtectedCustomRoots() throws {
        let home = try TempHome()
        for custom in ["", "Library", "Library/Caches", "Documents", "Library/Developer/Xcode/UserData"] {
            var env = home.env
            env.customDerivedData = home.url.appendingPathComponent(custom, isDirectory: true)
            let item = try home.file(custom.isEmpty ? "victim.txt" : "\(custom)/victim.txt")
            #expect(throws: GuardError.self, "custom root '\(custom)'") {
                try Guard.check(remove(item), category: category(.derivedData, in: env), home: home.url)
            }
        }
    }

    @Test func refusesRootsOutsideHome() throws {
        let home = try TempHome()
        let outside = try TempHome()
        var env = home.env
        env.customDerivedData = outside.url
        let item = try outside.file("App-abc/x").deletingLastPathComponent()
        #expect(throws: GuardError.self) {
            try Guard.check(remove(item), category: category(.derivedData, in: env), home: home.url)
        }
    }

    @Test func refusesSimctlAllAndUnexpectedShapes() throws {
        let home = try TempHome()
        let runtimes = category(.runtimes, in: home.env)
        let devices = category(.simulatorDevices, in: home.env)
        func simctl(_ args: [String], _ id: CategoryID) -> Action {
            Action(category: id, kind: .simctl(args), label: "", bytes: 0)
        }
        let bad: [([String], XPungeCore.Category)] = [
            (["runtime", "delete", "all"], runtimes),
            (["runtime", "delete", "21A328"], runtimes),  // builds are resolved to UUIDs first
            (["runtime", "delete", "--notUsedSinceDays", "1"], runtimes),
            (["delete", "all"], devices),
            (["erase", "all"], devices),
            (["--set", "previews", "delete", "unavailable"], devices),  // wrong set for this category
        ]
        for (args, cat) in bad {
            #expect(throws: GuardError.self, "\(args)") {
                try Guard.check(simctl(args, cat.id), category: cat, home: home.url)
            }
        }
        try Guard.check(simctl(["delete", "unavailable"], .simulatorDevices), category: devices, home: home.url)
        try Guard.check(simctl(["runtime", "delete", "178757CA-BA71-44B0-BDFD-C7BB36335306"], .runtimes),
                        category: runtimes, home: home.url)
    }

    @Test func refusesFileRemovalForSimctlCategories() throws {
        let home = try TempHome()
        let device = try home.folder("Library/Developer/CoreSimulator/Devices/ABC")
        #expect(throws: GuardError.self) {
            try Guard.check(remove(device, .simulatorDevices), category: category(.simulatorDevices, in: home.env), home: home.url)
        }
    }
}
