# Sweep

A native macOS cleaner and optimizer written in Swift and SwiftUI. It finds junk, uninstalls apps
completely, removes leftovers of apps you already deleted, finds large files, manages launch agents
and runs maintenance routines.

## Features

| Module | What it does |
| --- | --- |
| **Smart Scan** | Runs System Junk, Leftovers and the launch-agent check in one pass, then cleans what each module selects by default. |
| **System Junk** | User caches (skips running apps), logs, crash reports, old temp files, Xcode junk (DerivedData, device support, simulator caches), package manager caches (npm, Yarn, Gradle, Cargo, Bun…), broken preferences, broken launch agents, Mail attachment copies, iOS firmware, the Trash, system caches/logs, iOS backups and installers in Downloads. |
| **Large & Old Files** | Walks your home folder for files over a size threshold, filters by kind and by last use. |
| **Uninstaller** | Lists apps in /Applications and ~/Applications with size and last-opened date, and finds their containers, group containers, preferences, caches, saved state, cookies, launch agents, privileged helpers and /var/folders data. **Reset App** removes the data but keeps the app. |
| **Leftovers** | Finds support files named after bundle IDs that no installed app, helper, plug-in or running process owns. Groups that might be shared or were changed recently are flagged for review and left unselected. |
| **Optimization** | Enables, disables or removes launch agents and daemons, and shows memory use and the heaviest apps with Quit / Force Quit. |
| **Maintenance** | Free up RAM, flush DNS, rebuild Launch Services, reindex Spotlight, thin Time Machine snapshots, compact Mail's database, clear font caches, delete unavailable simulators, verify the startup disk. |
| **Menu bar** | Live CPU, memory and disk stats with a Free Up RAM button. |

## Building

Requirements: macOS 14 or later, Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
```

```bash
open Sweep.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Release -derivedDataPath build/DerivedData build
```

The app lands in `build/DerivedData/Build/Products/Release/Sweep.app`.

The project is signed ad hoc ("Sign to Run Locally"). macOS ties Full Disk Access to the signature,
so with ad hoc signing you have to grant it again after each rebuild. To avoid that, set your team in
Xcode under Signing & Capabilities.

## Permissions

- **Full Disk Access**: without it macOS hides the Trash, Mail downloads, device backups and other
  apps' containers. Grant it in System Settings › Privacy & Security › Full Disk Access (the app links
  there), then relaunch Sweep.
- **Administrator password**: asked through the standard macOS dialog only when a task needs root
  (system caches and logs, /Library launch daemons, root-owned apps, Free Up RAM, Flush DNS…).
- The app is **not sandboxed**. A sandboxed app can't reach other apps' Library folders, so a cleaner
  can't be distributed through the Mac App Store in this form. Distribute it with a Developer ID
  signature and notarization instead.

## Safety design

- Every deletion goes through `SafetyPolicy` ([Sweep/Core/SafetyPolicy.swift](Sweep/Core/SafetyPolicy.swift)), which refuses
  system locations, whole Library category folders, standard home folders, iCloud Drive, cloud storage,
  Keychains, Mail and Photos data, and anything outside the home folder, /Library, /Applications,
  /private/var/folders, /private/tmp and /private/var/log. Only `.app` bundles can be removed from the
  Applications folders.
- Uninstalled apps, leftovers and large files always go to the **Trash**. Junk is deleted immediately by
  default, which you can change in Settings.
- Items that need root are retried only when you ask, with one password prompt for the batch.
- Some things are deliberately left out: removing language files or thinning universal binaries breaks
  code signatures and can stop apps from launching. Malware detection needs a signature database.

## Tests

```bash
xcodebuild -project Sweep.xcodeproj -scheme Sweep -derivedDataPath build/DerivedData test
```

Unit tests cover the safety policy and bundle-ID matching. The read-only smoke tests scan the real
machine and print what each module would find (nothing is removed):

```bash
TEST_RUNNER_SWEEP_SMOKE=1 xcodebuild -project Sweep.xcodeproj -scheme Sweep -derivedDataPath build/DerivedData test -only-testing:SweepTests/ScanSmokeTests
```

## App icon

The icon is drawn in code. To change it, edit [Tools/make-icon.swift](Tools/make-icon.swift) and run:

```bash
swift Tools/make-icon.swift Sweep/Resources/Assets.xcassets/AppIcon.appiconset
```

## Layout

```
Sweep/
  App/          entry point, sidebar modules, settings, menu bar
  Core/         file scanning, safety policy, removal, shell/admin runner, app catalog, system stats
  Modules/      scanners: SystemJunk, Applications (uninstaller + leftovers), LargeFiles, Optimization, Maintenance
  Views/        one model + view per module, shared components
SweepTests/     Swift Testing unit and smoke tests
Tools/          icon generator
project.yml     XcodeGen project definition
```

## License

MIT. See [LICENSE](LICENSE).
