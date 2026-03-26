# Phase 4: App Exclusion - Research

**Researched:** 2026-03-26
**Domain:** macOS app detection, frontmost-app observation, fullscreen/borderless window detection, SwiftUI settings UI
**Confidence:** HIGH (core APIs), MEDIUM (fullscreen geometry heuristics)

---

## Summary

Phase 4 introduces two orthogonal suppression mechanisms for the hotkey: (1) a manual exclusion list stored as bundle IDs in UserDefaults, and (2) an automatic fullscreen/borderless-window detector based on CGWindowListCopyWindowInfo geometry comparison. Both checks run in `startRecording()` before audio begins.

The primary signal — per the locked decision from Phase 1 planning — is the explicit bundle ID list. Geometry-based fullscreen detection is the opt-in secondary toggle, explicitly to avoid suppressing the hotkey while a developer is using fullscreen Xcode or Terminal. The Exclusion settings tab adds a new `TabView` case to the existing `SettingsView`, containing an `NSMetadataQuery`-powered installed-apps list with search and `Toggle(.checkbox)`.

There is a known macOS 26 beta regression (FB18327911) in `CGWindowListCopyWindowInfo` affecting status-item ownership attribution. It does NOT affect window bounds or PID lookup used for fullscreen detection, so the geometry approach remains safe on the current build target (macOS 13+).

**Primary recommendation:** Wire the exclusion check as a guard in `AppDelegate.startRecording()` and `handleFlagsChanged()`. Build a dedicated `AppExclusionService` that owns the NSMetadataQuery for installed-apps discovery, the UserDefaults-backed exclusion set, and the frontmost-app/fullscreen query. The Exclusion tab in Settings reads from and writes to that service via `@EnvironmentObject`.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EXCL-01 | User can select apps to exclude from an installed apps picker (no manual bundle ID entry) | NSMetadataQuery finds all installed apps; Bundle(url:).bundleIdentifier extracts ID; NSWorkspace.icon(forFile:) provides icons |
| EXCL-02 | Hotkey is auto-suppressed when frontmost app is in fullscreen or borderless-windowed mode | CGWindowListCopyWindowInfo with kCGWindowBounds + screen frame comparison; auto-suppress is opt-in toggle |
| EXCL-03 | Settings includes an Exclusion tab with installed apps list, search, and checkboxes | New SettingsTab.exclusion case; List + .searchable modifier + Toggle(.checkbox) per row |
</phase_requirements>

---

## Standard Stack

### Core

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| `NSWorkspace.shared.frontmostApplication` | AppKit (macOS 10.6+) | Get current frontmost app bundle ID | Official Apple API, synchronous, zero permissions |
| `NSWorkspace.shared.notificationCenter` + `didActivateApplicationNotification` | AppKit | Observe app focus changes reactively | Push-based, no polling; preferred over polling |
| `CGWindowListCopyWindowInfo` | CoreGraphics (macOS 10.5+) | Query per-window bounds of the frontmost app | Only stable public API for window geometry of other processes |
| `NSMetadataQuery` | Foundation | Enumerate all installed `.app` bundles via Spotlight | Covers /Applications, ~/Applications, and sub-folders; no file-system crawl needed |
| `UserDefaults.standard` | Foundation | Persist exclusion bundle ID set | `stringArray(forKey:)` natively stores `[String]` |
| `Toggle(.checkbox)` / `CheckboxToggleStyle` | SwiftUI | Per-app checkbox in settings list | macOS-native checkbox pattern; `.toggleStyle(.checkbox)` |
| `.searchable(text:)` | SwiftUI | Filter apps in exclusion list | Built-in SwiftUI modifier, macOS 12+ |

### Supporting

| Library / API | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| `NSWorkspace.icon(forFile:)` | AppKit | App icon for installed apps list | Display alongside app name in list |
| `Bundle(url:).bundleIdentifier` | Foundation | Extract bundle ID from `.app` URL | Used during NSMetadataQuery result processing |
| `NSScreen.main?.frame` | AppKit | Get full screen dimensions for fullscreen comparison | Required for geometry-based fullscreen test |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSMetadataQuery | FileManager enumeration of /Applications | NSMetadataQuery covers all standard install paths (App Store, Homebrew Cask, user ~/Applications) without manual recursion |
| NSMetadataQuery | LSApplicationWorkspace.default().allInstalledApplications() | LSApplicationWorkspace is private API — App Store rejection risk |
| CGWindowListCopyWindowInfo | ScreenCaptureKit SCShareableContent | ScreenCaptureKit requires screen recording permission; unacceptable for a check that runs on every hotkey press |
| didActivateApplicationNotification | Polling NSWorkspace.frontmostApplication on a timer | Notification is push-based and more efficient |

**Installation:** No new packages — all APIs are in AppKit, Foundation, CoreGraphics, and SwiftUI (already linked).

---

## Architecture Patterns

### Recommended Project Structure

```
FlowSpeech/
├── Services/
│   ├── AppExclusionService.swift   # NEW — owns NSMetadataQuery, exclusion set, fullscreen check
│   ├── HotkeyManager.swift         # unchanged
│   └── ...
├── Views/
│   ├── SettingsView.swift          # add .exclusion tab case
│   ├── ExclusionSettingsTab.swift  # NEW — installed apps list UI
│   └── ...
└── FlowSpeechApp.swift             # AppState gets excludedBundleIDs + autoSuppressFullscreen
```

### Pattern 1: AppExclusionService — Centralized Suppression Logic

**What:** A class that owns the installed-apps list, the exclusion set, and the should-suppress query. AppDelegate calls `exclusionService.shouldSuppressHotkey()` before starting recording.

**When to use:** Keeps AppDelegate from growing. All exclusion logic in one testable unit.

```swift
// AppExclusionService.swift
import AppKit
import Foundation
import CoreGraphics

class AppExclusionService: ObservableObject {

    // MARK: - Persisted State

    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { persist() }
    }
    @Published var autoSuppressFullscreen: Bool = true {
        didSet { UserDefaults.standard.set(autoSuppressFullscreen, forKey: "autoSuppressFullscreen") }
    }

    // MARK: - Installed Apps (for picker)

    @Published var installedApps: [InstalledApp] = []

    struct InstalledApp: Identifiable, Comparable {
        let id: String            // bundle ID
        let name: String
        let icon: NSImage
        static func < (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.name < rhs.name }
    }

    private var metadataQuery: NSMetadataQuery?

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? []
        excludedBundleIDs = Set(saved)
        autoSuppressFullscreen = UserDefaults.standard.object(forKey: "autoSuppressFullscreen")
            .flatMap { $0 as? Bool } ?? true
    }

    // MARK: - Hotkey Suppression Gate

    /// Call this at the top of startRecording(). Returns true = suppress.
    func shouldSuppressHotkey() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier else { return false }

        // 1. Manual exclusion list
        if excludedBundleIDs.contains(bundleID) { return true }

        // 2. Auto fullscreen detection (opt-in)
        if autoSuppressFullscreen {
            return frontmostAppIsFullscreenOrBorderless(pid: frontmost.processIdentifier)
        }
        return false
    }

    // MARK: - Fullscreen Detection

    private func frontmostAppIsFullscreenOrBorderless(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.main else { return false }

        let screenFrame = screen.frame  // NSScreen coords
        // CGWindow bounds use flipped coordinates; convert height
        let screenH = screenFrame.height

        for window in list {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  let x = boundsDict["X"], let y = boundsDict["Y"] else { continue }

            // Borderless windows that cover the full screen
            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            let fullWidth  = abs(w - screenFrame.width) < 2
            let fullHeight = abs(h - screenH) < 2

            if fullWidth && fullHeight { return true }

            // NSWindow fullscreen mode: window height == screen height, x == 0, y == 0
            // (generous tolerance for menu-bar auto-hide and notch macs)
            let coversScreen = w >= screenFrame.width * 0.99 && h >= screenH * 0.95
            if coversScreen { return true }
        }
        return false
    }

    // MARK: - Installed Apps Discovery

    func startInstalledAppsQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = ["/Applications", NSHomeDirectory() + "/Applications"]
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemDisplayName as String, ascending: true)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinish(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        metadataQuery = query
        query.start()
    }

    @objc private func queryDidFinish(_ note: Notification) {
        guard let query = note.object as? NSMetadataQuery else { return }
        query.stop()

        var apps: [InstalledApp] = []
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }
            let name = (item.value(forAttribute: kMDItemDisplayName as String) as? String) ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path)
            apps.append(InstalledApp(id: bundleID, name: name, icon: icon))
        }

        DispatchQueue.main.async {
            self.installedApps = apps.sorted()
        }
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")
    }
}
```

### Pattern 2: Exclusion Gate in AppDelegate.startRecording()

```swift
// In AppDelegate.startRecording(), add as first guard:
func startRecording() {
    guard appState.phase != .recording else { return }
    guard !exclusionService.shouldSuppressHotkey() else {
        // Silently suppress — no sound, no overlay
        return
    }
    // ... existing code
}
```

### Pattern 3: ExclusionSettingsTab — Installed Apps Picker

```swift
struct ExclusionSettingsTab: View {
    @EnvironmentObject var exclusionService: AppExclusionService
    @State private var searchText = ""

    var filteredApps: [AppExclusionService.InstalledApp] {
        if searchText.isEmpty { return exclusionService.installedApps }
        return exclusionService.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Auto-suppress in fullscreen apps", isOn: $exclusionService.autoSuppressFullscreen)
            } header: {
                Text("Automatic Suppression")
            }

            Section {
                List(filteredApps) { app in
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable().frame(width: 24, height: 24)
                        Text(app.name)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { exclusionService.excludedBundleIDs.contains(app.id) },
                            set: { isOn in
                                if isOn { exclusionService.excludedBundleIDs.insert(app.id) }
                                else { exclusionService.excludedBundleIDs.remove(app.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                }
                .searchable(text: $searchText, prompt: "Search apps...")
                .frame(minHeight: 200)
            } header: {
                Text("Excluded Apps")
            }
        }
        .formStyle(.grouped)
        .onAppear { exclusionService.startInstalledAppsQuery() }
    }
}
```

### Pattern 4: Wiring into AppState and SettingsView

```swift
// SettingsView.swift — add new tab case
enum SettingsTab: String, CaseIterable {
    case general, hotkey, transcription, api, exclusion, about
}

// In TabView:
ExclusionSettingsTab()
    .tabItem { Label("Exclusion", systemImage: "hand.raised") }
    .tag(SettingsTab.exclusion)

// AppDelegate — add service instance and pass as environmentObject
let exclusionService = AppExclusionService()

// In openSettings():
let settingsView = SettingsView()
    .environmentObject(appState)
    .environmentObject(exclusionService)
```

### Pattern 5: Frontmost App Observation (Reactive)

Observing `NSWorkspace.didActivateApplicationNotification` is optional for Phase 4. The simpler synchronous `shouldSuppressHotkey()` call in `handleFlagsChanged` is sufficient and avoids race conditions. Reactive observation would be needed only if we want to show a status indicator in the menu bar for excluded apps.

### Anti-Patterns to Avoid

- **Polling frontmostApplication on a timer:** CPU waste, latency. Use the notification for reactive updates or the synchronous query directly in the hotkey handler.
- **Storing bundle IDs as a comma-joined String:** Use `stringArray(forKey:)` — it natively handles `[String]` arrays.
- **Using ScreenCaptureKit for window geometry:** It requires screen-recording permission and an async flow that's impractical on every hotkey press.
- **Using LSApplicationWorkspace:** Private API, App Store rejection risk, and `allInstalledApplications()` is undocumented.
- **Fetching apps in the view body or on `@State` load:** NSMetadataQuery is async; always start it in `onAppear` and publish results to `@Published`.
- **Using `NSScreen.main.frame.size` as the sole fullscreen test:** Notch Macs and auto-hiding menu bars can produce false negatives. Use a 99%/95% coverage tolerance.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Enumerate all installed apps | FileManager recursive /Applications scan | NSMetadataQuery with Spotlight | Covers App Store apps in non-standard paths, handles aliases, sorted by Spotlight metadata |
| Get app icon | Manual Info.plist parsing + image load | `NSWorkspace.shared.icon(forFile:)` | Handles all icon formats, sizes, and fallbacks automatically |
| Persist exclusion set | Custom file encoding | `UserDefaults.stringArray(forKey:)` | String arrays are natively supported, no serialization code needed |
| Detect frontmost app | Polling or CGWindowServer queries | `NSWorkspace.shared.frontmostApplication` | Synchronous, no permissions, official API |

**Key insight:** The risk in this domain is over-engineering. The exclusion check runs on every hotkey keydown event; it must be synchronous, cheap, and reliable. All required data is available via first-party AppKit and CoreGraphics calls in under 1ms.

---

## Common Pitfalls

### Pitfall 1: CGWindowListCopyWindowInfo macOS 26 Beta Regression (FB18327911)

**What goes wrong:** The reported regression causes status-item windows to attribute ownership to Control Center instead of the originating app. This **does not affect** the use case here — we query by `kCGWindowOwnerPID` matching the `processIdentifier` of `NSWorkspace.frontmostApplication`, so the PID lookup is not affected by status-item attribution changes.

**How to avoid:** Use `kCGWindowOwnerPID` comparison, not `kCGWindowOwnerName`. Validated against the specific regression.

**Warning signs:** If all windows return `pid == Control Center PID`, the regression has broadened. Fallback: disable fullscreen auto-suppress and rely solely on manual exclusion list.

### Pitfall 2: NSMetadataQuery Must Be Run on Main Thread (or with proper RunLoop)

**What goes wrong:** NSMetadataQuery started on a background thread without a RunLoop attached never fires `NSMetadataQueryDidFinishGathering`.

**How to avoid:** Always call `query.start()` from the main thread or ensure the calling thread has an active RunLoop. In the pattern above, `startInstalledAppsQuery()` is called from `onAppear`, which runs on the main actor.

**Warning signs:** `installedApps` remains empty after several seconds.

### Pitfall 3: NSMetadataQuery Scope Gaps

**What goes wrong:** Limiting search scope to only `/Applications` misses apps in `~/Applications`, `/Applications/Setapp/`, and other install locations.

**How to avoid:** Include `NSHomeDirectory() + "/Applications"` in `query.searchScopes`. Optionally add `NSMetadataQueryLocalComputerScope` but be aware this can be slow.

**Warning signs:** Apps like Setapp titles or homebrew-cask apps installed in ~/Applications don't appear in the list.

### Pitfall 4: Bundle(url:) Returns nil for Non-Bundle .app Packages

**What goes wrong:** Corrupted or non-standard `.app` bundles may not produce a valid `Bundle` instance. `bundleIdentifier` returns nil for apps without a proper Info.plist.

**How to avoid:** Guard on `bundle.bundleIdentifier != nil` before adding to the results array. Skip silently.

### Pitfall 5: Fullscreen False Positives with Fullscreen Xcode/Terminal

**What goes wrong:** Geometry-based detection treats fullscreen Xcode or Terminal as games and suppresses dictation — a primary use case of the app.

**How to avoid:** This is exactly why the auto-suppress is an **opt-in toggle** (defaulting to true, per EXCL-02 requirement). Users who work in fullscreen development environments can disable it. The manual exclusion list remains the primary, always-on signal.

### Pitfall 6: SettingsView Frame Too Small for New Tab

**What goes wrong:** Current `SettingsView` frame is 500x400. An exclusion list with 50+ apps requires a taller or scrollable frame.

**How to avoid:** The `List` inside `ExclusionSettingsTab` handles scrolling internally. Set `minHeight: 200` on the List (not the window). Consider expanding the window height to 500 or 520 when the Exclusion tab is active, or set a fixed taller frame on the settings window.

### Pitfall 7: Default Exclusion List

**What goes wrong:** User with League of Legends installed expects it to be auto-excluded without manual setup.

**How to avoid:** Seed `excludedBundleIDs` with a known default list on first launch (check `UserDefaults.object(forKey:) == nil` to detect first run). Verified bundle IDs: `com.riotgames.LeagueofLegends` (game client) and `com.riotgames.LeagueofLegends.LeagueClientUx` (launcher). Mark these as pre-checked in the UI but allow removal.

---

## Code Examples

### Getting Frontmost App Bundle ID (synchronous, zero permissions)

```swift
// Source: Apple Developer Documentation — NSWorkspace.frontmostApplication
if let frontmost = NSWorkspace.shared.frontmostApplication,
   let bundleID = frontmost.bundleIdentifier {
    print(bundleID) // e.g. "com.riotgames.LeagueofLegends"
}
```

### Observing App Focus Changes (reactive, Combine)

```swift
// Source: Apple Developer Documentation — NSWorkspace.didActivateApplicationNotification
NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didActivateApplicationNotification)
    .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
    .sink { app in
        print("Frontmost changed to: \(app.bundleIdentifier ?? "unknown")")
    }
    .store(in: &cancellables)
```

### UserDefaults Store/Retrieve Exclusion Set

```swift
// Store
UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")
// Retrieve
let ids = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
```

### SwiftUI Checkbox Toggle for Exclusion Row

```swift
// Source: Apple Developer Documentation — CheckboxToggleStyle (macOS)
Toggle("", isOn: $isExcluded)
    .toggleStyle(.checkbox)
    .labelsHidden()
```

### NSMetadataQuery Start Pattern

```swift
// Source: Apple Developer Documentation — NSMetadataQuery
let query = NSMetadataQuery()
query.searchScopes = ["/Applications", NSHomeDirectory() + "/Applications"]
query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")

NotificationCenter.default.addObserver(
    forName: .NSMetadataQueryDidFinishGathering,
    object: query,
    queue: .main
) { _ in
    query.stop()
    // process query.results
}
query.start() // must be called on main thread
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CGWindowListCreateImage for window capture | ScreenCaptureKit SCScreenshotManager | macOS 14 deprecated CGWindowListCreateImage | Does not affect us — we only need window bounds, not image capture |
| Manual /Applications folder crawl | NSMetadataQuery with kMDItemContentType | macOS 10.4+ (Spotlight era) | Covers more install locations reliably |
| Polling frontmostApplication | NSWorkspace.didActivateApplicationNotification | AppKit longstanding | More efficient but synchronous query also valid for single hotkey checks |

**Deprecated/outdated:**
- `CGWindowListCreateImage`: Deprecated in macOS 14, unavailable in macOS 15. Not used here.
- `NSWorkspace.activeApplication()` (ObjC): Returns a dictionary; replaced by `NSWorkspace.frontmostApplication` returning `NSRunningApplication`. Do not use the dictionary form.

---

## Open Questions

1. **macOS minimum deployment target**
   - What we know: STATE.md notes the target is unresolved; Phase 1 used `#available(macOS 13.0, *)` for SMAppService.
   - What's unclear: `.searchable` requires macOS 12; `CheckboxToggleStyle` requires macOS 10.15. If target is macOS 12+, all APIs are available.
   - Recommendation: Confirm the deployment target before implementation. If macOS 12+ is the minimum, all Phase 4 APIs are available without `#available` guards.

2. **Default auto-suppress behavior**
   - What we know: EXCL-02 says suppress when "auto-suppress toggle is enabled" — implies it can be disabled.
   - What's unclear: Should it default on or off? Given the primary use case (gaming), defaulting to `true` is correct but may surprise developers.
   - Recommendation: Default `autoSuppressFullscreen = true`, document the toggle clearly in the UI with a label like "Suppress in fullscreen apps (games, video players)".

3. **League of Legends bundle IDs**
   - What we know: STATE.md lists both `com.riotgames.LeagueofLegends` and `com.riotgames.LeagueofLegends.LeagueClientUx` as candidates.
   - What's unclear: The actual bundle IDs have not been verified on a live install.
   - Recommendation: Include both in the default seed list; if one doesn't match any installed app it will simply have no effect.

---

## Validation Architecture

> `workflow.nyquist_validation` is not set to `false` in config.json — validation architecture section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — this is a native macOS SwiftUI app; no XCTest configured in the project |
| Config file | None |
| Quick run command | Build in Xcode + manual hotkey test |
| Full suite command | N/A |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXCL-01 | Installed apps list populates with names + icons + checkboxes in Exclusion tab | Manual-only | — | N/A |
| EXCL-01 | Search field filters app list | Manual-only | — | N/A |
| EXCL-01 | Checking app persists to UserDefaults and survives relaunch | Manual-only | — | N/A |
| EXCL-02 | Hotkey suppressed when excluded app is frontmost | Manual-only | — | N/A |
| EXCL-02 | Auto-suppress toggle disables fullscreen suppression | Manual-only | — | N/A |
| EXCL-03 | Exclusion tab appears in Settings window | Manual-only | — | N/A |

**Note:** There is no XCTest infrastructure in this project. All validation is manual functional testing. The `shouldSuppressHotkey()` logic is simple enough to test with pure-Swift unit tests if desired; the recommended Wave 0 gap is adding `AppExclusionServiceTests.swift` targeting the suppression logic with mock NSRunningApplication data.

### Sampling Rate

- **Per task commit:** Build succeeds in Xcode (Cmd+B)
- **Per wave merge:** Manual smoke test of hotkey suppression with excluded app focused
- **Phase gate:** All three success criteria verified manually before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] No test files exist — add `AppExclusionServiceTests.swift` if unit testing `shouldSuppressHotkey()` is desired
- [ ] No XCTest configuration — manual testing is the established pattern for this project

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — [NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) — synchronous frontmost app lookup
- Apple Developer Documentation — [NSWorkspace.didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification) — reactive app focus observation
- Apple Developer Documentation — [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) — window bounds for fullscreen detection
- Apple Developer Documentation — [NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery) — Spotlight-based installed-apps enumeration
- Apple Developer Documentation — [CheckboxToggleStyle](https://developer.apple.com/documentation/swiftui/checkboxtogglestyle) — macOS checkbox in SwiftUI

### Secondary (MEDIUM confidence)

- GitHub feedback-assistant/reports [FB18327911](https://github.com/feedback-assistant/reports/issues/679) — macOS 26 beta CGWindowListCopyWindowInfo status-item regression; confirmed does not affect PID-based window bounds queries
- Cocoacasts — [How to Store an Array in UserDefaults](https://cocoacasts.com/ud-3-how-to-store-an-array-in-user-defaults-in-swift) — confirms `stringArray(forKey:)` natively handles `[String]`

### Tertiary (LOW confidence)

- Apple Developer Forums thread/792917 — fullscreen detection approaches; page was JavaScript-only, content not verified; kCGWindowBounds geometry approach cross-verified with official CGWindowListCopyWindowInfo docs

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — All APIs are official AppKit/CoreGraphics/SwiftUI, cross-verified with Apple docs
- Architecture: HIGH — Patterns follow existing project conventions (service class + @EnvironmentObject); AppExclusionService mirrors HotkeyManager pattern
- Fullscreen geometry heuristics: MEDIUM — kCGWindowBounds approach is correct but tolerance values (99%/95%) are empirically derived; may need tuning for edge cases (auto-hide menu bar, notch Macs)
- Pitfalls: HIGH — FB18327911 regression confirmed via GitHub; NSMetadataQuery threading from documented behaviour; false-positive risk from project STATE.md notes

**Research date:** 2026-03-26
**Valid until:** 2026-06-26 (stable APIs; CGWindowListCopyWindowInfo regression resolved or documented workaround expected before macOS 26 ships)
