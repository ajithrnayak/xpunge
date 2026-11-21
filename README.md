# xpunge

[![CI](https://github.com/ajithrnayak/xpunge/actions/workflows/ci.yml/badge.svg)](https://github.com/ajithrnayak/xpunge/actions/workflows/ci.yml)

See how much disk space Xcode uses, and reclaim it safely.

Xcode quietly fills tens of gigabytes: simulator runtimes, DerivedData, package caches, Previews devices, device support files. `xpunge` measures all of it and removes what's safe to remove. For anything Apple manages through `simctl`, it goes through `simctl` instead of deleting folders by hand.

```
$ xpunge scan
+--------------------+-----------+-------------+------------------------------------+
|                                    xpunge scan                                    |
+--------------------+-----------+-------------+------------------------------------+
| Category           |      Size | Clean       | Note                               |
+--------------------+-----------+-------------+------------------------------------+
| runtimes           |   62.6 GB | by name     | 8 runtimes, 4 with no recorded use |
| simulator-devices  |  11.46 GB | default     | 21 unavailable (1.72 GB)           |
| swiftpm-cache      |   9.37 GB | default     |                                    |
| previews           |   8.56 GB | default     | 3 unavailable (3.57 GB)            |
| playground-devices |   5.94 GB | report only |                                    |
| xcode-apps         |   4.24 GB | report only | 1 installed                        |
| xcodes-downloads   |    3.4 GB | by name     | includes unfinished downloads      |
| cocoapods-cache    |   1.84 GB | default     |                                    |
| documentation      |    553 MB | default     |                                    |
| derived-data       |    187 MB | default     | includes compilation cache (29 KB) |
| …                  |           |             |                                    |
+--------------------+-----------+-------------+------------------------------------+
| Total              | 108.15 GB |             | a plain clean frees about 17.25 GB |
+--------------------+-----------+-------------+------------------------------------+

Voilà! 🧐 Xcode is using 108.15 GB here; a plain clean frees about 17.25 GB.
Cleaned only when named: runtimes (62.6 GB), xcodes-downloads (3.4 GB).
Preview a clean with `xpunge clean --dry-run`.
```

> **Status: early (v0.1.1).** Tested on Xcode 26.2 and 27.2. Start with `xpunge clean --dry-run`, and please [report anything odd](https://github.com/ajithrnayak/xpunge/issues).

## Install

With Homebrew:

```sh
brew install ajithrnayak/tap/xpunge
```

Or download the universal binary yourself (Apple silicon and Intel, macOS 13 or later):

```sh
curl -LO https://github.com/ajithrnayak/xpunge/releases/download/v0.1.1/xpunge-0.1.1-macos-universal.tar.gz
curl -LO https://github.com/ajithrnayak/xpunge/releases/download/v0.1.1/xpunge-0.1.1-macos-universal.tar.gz.sha256
shasum -a 256 -c xpunge-0.1.1-macos-universal.tar.gz.sha256
tar -xzf xpunge-0.1.1-macos-universal.tar.gz
mv xpunge /usr/local/bin/   # or anywhere on your PATH
```

The binary isn't notarized yet. Downloading with `curl` as above avoids Gatekeeper's block. If you downloaded it in a browser and macOS refuses to open it, run `xattr -d com.apple.quarantine xpunge`.

From source (needs Swift 6 and macOS 13 or later):

```sh
git clone https://github.com/ajithrnayak/xpunge.git
cd xpunge
swift build -c release
cp .build/release/xpunge /usr/local/bin/   # or anywhere on your PATH
```

## Usage

```sh
xpunge scan                      # size of every category, largest first (read-only)
xpunge scan --details            # list what's inside each category
xpunge scan runtimes --json      # machine-readable output

xpunge clean --dry-run           # show exactly what a clean would remove
xpunge clean                     # clean the safe default set, after confirmation
xpunge clean derived-data swiftpm-cache

xpunge clean runtimes --not-used-since 180 --dry-run
xpunge clean runtimes --runtime 21A328          # by build or UUID
xpunge clean device-support --keep-latest 2
xpunge clean archives                           # only ever when named
```

`clean` always shows its plan first and asks before removing anything. It refuses to run while Xcode or Simulator is open, and refuses to run without a terminal unless you pass `--yes`. Removal is permanent: moving items to the Trash wouldn't free any space until the Trash was emptied.

Exit codes: `0` done, `1` error, `2` some items failed, `3` refused for safety.

In a terminal, success messages open with a random interjection and emoji ("Woohoo! 🎉 xpunge freed about 17.25 GB."). Piped output stays plain. Set `XPUNGE_PLAIN=1` to turn the fun off, or `NO_COLOR=1` to turn off colour.

## Categories

| Category | What | Cleaned |
|---|---|---|
| `derived-data` | `~/Library/Developer/Xcode/DerivedData`, including the compilation cache | default |
| `xcode-cache` | Xcode's caches, old build products, device logs | default |
| `swiftpm-cache` | `~/Library/Caches/org.swift.swiftpm` | default |
| `cocoapods-cache` | `~/Library/Caches/CocoaPods` | default |
| `carthage-cache` | `~/Library/Caches/org.carthage.CarthageKit` | default |
| `documentation` | Documentation cache and index, together | default |
| `simulator-caches` | `~/Library/Developer/CoreSimulator/Caches` | default |
| `simulator-devices` | Unavailable simulators only, via `simctl delete unavailable` | default |
| `previews` | Unavailable SwiftUI Previews devices only, via `simctl --set previews` | default |
| `test-devices` | Unavailable parallel-testing clones only, via `simctl --set testing` | default |
| `runtimes` | Simulator runtimes, one `simctl runtime delete <uuid>` each | by name, with `--runtime` or `--not-used-since` |
| `device-support` | iOS, watchOS, tvOS and visionOS DeviceSupport | by name |
| `archives` | `~/Library/Developer/Xcode/Archives` (contains your dSYMs) | by name |
| `xcodes-downloads` | `.xip` files left by the Xcodes app | by name |
| `playground-devices` | `~/Library/Developer/XCPGDevices` | report only, for now |
| `xcode-apps` | Installed Xcode copies | report only, never removed |

## Safety

- **Nothing outside a known category is touched.** `clean` only removes items directly inside a category's own folders, inside your home folder. Every action is checked twice: once when the plan is built and again just before it runs.
- **Simulator data goes through `simctl`.** Runtimes are system-managed disk images; deleting their folders by hand breaks things. Runtime sizes come from `simctl runtime list`, never from `du`, because `du` can both over- and undercount them.
- **Never `all`.** `xpunge` never passes `all` to `simctl`. `--not-used-since` keeps the runtimes any installed Xcode in `/Applications` uses (asked through each Xcode's own `simctl runtime match list`) unless you name them. If one can't be checked, the plan says so. A runtime's age is its last use, or its install date if that's later, because Xcode 26 and later leave the last-use date empty for most runtimes.
- **No sudo.** It never needs it and never asks for it.
- **Finds Xcode itself.** `xcode-select` often points at the Command Line Tools, which have no `simctl`. `xpunge` uses `DEVELOPER_DIR` first, then `xcode-select`, then the newest `/Applications/Xcode*.app`. If it can't find a full Xcode, the `simctl` categories are skipped and only reported.

## Development

```sh
swift build
swift test
```

If `xcode-select` points at the Command Line Tools, point the build at a full Xcode with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

The tests never touch your real `~/Library` or simulators. Each one builds a fixture tree in a temp folder, and `simctl` is replaced by a fake that serves JSON captured from real Xcode 26.2 and 27.2 installs (in `Tests/XPungeCoreTests/Fixtures`).

All logic lives in `XPungeCore`. The `xpunge` target only parses arguments and prints. `clean` runs in three stages: the `Planner` decides what to remove, the `Guard` checks each action, and the `Executor` runs them.

## License

MIT. See [LICENSE](LICENSE).
