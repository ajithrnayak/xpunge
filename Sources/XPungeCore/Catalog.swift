import Foundation

/// Every category xpunge knows about, with paths resolved for one environment.
/// Paths were checked on Xcode 26.2; see the project notes for what is still unverified.
public enum Catalog {
    public static func categories(in env: Environment) -> [Category] {
        let xcode = "Library/Developer/Xcode"
        let derivedData = env.customDerivedData ?? env.homePath("\(xcode)/DerivedData")
        let archives = env.customArchives ?? env.homePath("\(xcode)/Archives")

        return [
            Category(
                id: .derivedData, title: "DerivedData", policy: .byDefault, removal: .contents,
                roots: [derivedData],
                about: "Build products, indexes and the compilation cache. Rebuilt on the next build."
            ),
            Category(
                id: .xcodeCache, title: "Xcode caches", policy: .byDefault, removal: .contents,
                roots: [
                    env.homePath("Library/Caches/com.apple.dt.Xcode"),
                    env.homePath("Library/Caches/com.apple.dt.xcodebuild"),
                    env.homePath("\(xcode)/Products"),
                    env.homePath("\(xcode)/iOS Device Logs"),
                ],
                about: "Xcode's own caches, old build products and device logs."
            ),
            Category(
                id: .swiftpmCache, title: "SwiftPM cache", policy: .byDefault, removal: .contents,
                roots: [env.homePath("Library/Caches/org.swift.swiftpm")],
                about: "Downloaded package repositories and manifests. Fetched again when needed."
            ),
            Category(
                id: .cocoapodsCache, title: "CocoaPods cache", policy: .byDefault, removal: .contents,
                roots: [env.homePath("Library/Caches/CocoaPods")],
                about: "Downloaded pods. Fetched again on the next pod install."
            ),
            Category(
                id: .carthageCache, title: "Carthage cache", policy: .byDefault, removal: .contents,
                roots: [env.homePath("Library/Caches/org.carthage.CarthageKit")],
                about: "Downloaded Carthage dependencies."
            ),
            Category(
                id: .documentation, title: "Documentation", policy: .byDefault, removal: .contents,
                roots: [
                    env.homePath("\(xcode)/DocumentationCache"),
                    env.homePath("\(xcode)/DocumentationIndex"),
                ],
                about: "Documentation cache and its index, removed together. Xcode rebuilds them."
            ),
            Category(
                id: .simulatorCaches, title: "Simulator caches", policy: .byDefault, removal: .contents,
                roots: [env.homePath("Library/Developer/CoreSimulator/Caches")],
                about: "CoreSimulator caches. Rebuilt when a simulator boots."
            ),
            Category(
                id: .simulatorDevices, title: "Simulator devices", policy: .byDefault,
                removal: .unavailableDevices(.standard),
                roots: [env.homePath("Library/Developer/CoreSimulator/Devices")],
                about: "Only devices whose runtime is gone are removed (simctl delete unavailable)."
            ),
            Category(
                id: .previews, title: "SwiftUI Previews", policy: .byDefault,
                removal: .unavailableDevices(.previews),
                roots: [env.homePath("\(xcode)/UserData/Previews")],
                about: "Only unavailable Previews devices are removed (simctl --set previews)."
            ),
            Category(
                id: .testDevices, title: "Test device clones", policy: .byDefault,
                removal: .unavailableDevices(.testing),
                roots: [env.homePath("Library/Developer/XCTestDevices")],
                about: "Only unavailable parallel-testing clones are removed (simctl --set testing)."
            ),
            Category(
                id: .runtimes, title: "Simulator runtimes", policy: .namedOnly, removal: .runtimes,
                roots: [],
                about: "System disk images, removed one by one with simctl runtime delete. Needs --runtime or --not-used-since."
            ),
            Category(
                id: .deviceSupport, title: "Device support", policy: .namedOnly, removal: .contents,
                roots: ["iOS", "watchOS", "tvOS", "visionOS"].map { env.homePath("\(xcode)/\($0) DeviceSupport") },
                about: "Symbols copied from physical devices. Recreated when the device is attached again."
            ),
            Category(
                id: .archives, title: "Archives", policy: .namedOnly, removal: .contents,
                roots: [archives],
                about: "Contain the dSYMs needed to symbolicate crashes from shipped builds."
            ),
            Category(
                id: .xcodesDownloads, title: "Xcodes downloads", policy: .namedOnly,
                removal: .files(suffixes: [".xip", ".xip.aria2"]),
                roots: [env.homePath("Library/Application Support/com.robotsandpencils.XcodesApp")],
                about: "Xcode .xip files downloaded by the Xcodes app, including unfinished downloads."
            ),
            Category(
                id: .playgroundDevices, title: "Playground devices", policy: .scanOnly, removal: .none,
                roots: [env.homePath("Library/Developer/XCPGDevices")],
                about: "Simulator devices for playgrounds. Report only until the simctl command is verified."
            ),
            Category(
                id: .xcodeApps, title: "Xcode apps", policy: .scanOnly, removal: .none,
                roots: xcodeApps(in: env.applications),
                about: "Installed Xcode copies. Never removed by xpunge; use Xcodes or Finder."
            ),
        ]
    }

    static func xcodeApps(in applications: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: applications.path)) ?? []
        return names
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") && $0 != "Xcodes.app" }
            .sorted()
            .map { applications.appendingPathComponent($0, isDirectory: true) }
    }
}
