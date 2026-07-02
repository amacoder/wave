//
//  AppExclusionService.swift
//  Wave
//
//  Owns the manual exclusion list, installed-apps discovery (NSMetadataQuery),
//  and fullscreen/borderless-window detection (CGWindowListCopyWindowInfo).
//

import AppKit
import Foundation
import CoreGraphics

class AppExclusionService: ObservableObject {

    // MARK: - Nested Types

    struct InstalledApp: Identifiable, Comparable {
        let id: String            // bundle ID
        let name: String
        let icon: NSImage
        static func < (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Default Exclusion List

    static let defaultExcludedBundleIDs: Set<String> = [
        "com.riotgames.LeagueofLegends",
        "com.riotgames.LeagueofLegends.LeagueClientUx"
    ]

    // MARK: - Published State

    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { persist() }
    }

    @Published var autoSuppressFullscreen: Bool = true {
        didSet {
            UserDefaults.standard.set(autoSuppressFullscreen, forKey: "autoSuppressFullscreen")
        }
    }

    @Published var installedApps: [InstalledApp] = []

    // MARK: - Private Properties

    private var metadataQuery: NSMetadataQuery?

    /// CGWindowListCopyWindowInfo is too slow for the hotkey hot path, so the
    /// fullscreen result is cached per frontmost pid and refreshed on app switch.
    private var fullscreenCache: (pid: pid_t, at: Date, result: Bool)?
    private let fullscreenCacheTTL: TimeInterval = 2.0

    // MARK: - Init

    init() {
        // First launch: seed default exclusions
        if UserDefaults.standard.object(forKey: "excludedBundleIDs") == nil {
            excludedBundleIDs = Self.defaultExcludedBundleIDs
            persist()
        } else {
            let saved = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? []
            excludedBundleIDs = Set(saved)
        }

        // Load autoSuppressFullscreen, defaulting to true if never set
        if let stored = UserDefaults.standard.object(forKey: "autoSuppressFullscreen") as? Bool {
            autoSuppressFullscreen = stored
        } else {
            autoSuppressFullscreen = true
        }

        // Pre-warm the fullscreen cache whenever the user switches apps, so the
        // hotkey press itself never pays for the window-list scan.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostAppChanged(_ note: Notification) {
        guard autoSuppressFullscreen,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = self.computeFullscreenOrBorderless(pid: pid)
            DispatchQueue.main.async {
                self.fullscreenCache = (pid, Date(), result)
            }
        }
    }

    // MARK: - Hotkey Suppression Gate

    /// Returns true when the hotkey should be silently suppressed.
    /// Call this at the top of startRecording() before any audio begins.
    func shouldSuppressHotkey() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier else { return false }

        // 1. Manual exclusion list — always checked
        if excludedBundleIDs.contains(bundleID) { return true }

        // 2. Auto fullscreen detection — opt-in
        if autoSuppressFullscreen {
            return frontmostAppIsFullscreenOrBorderless(pid: frontmost.processIdentifier)
        }

        return false
    }

    // MARK: - Fullscreen Detection

    private func frontmostAppIsFullscreenOrBorderless(pid: pid_t) -> Bool {
        if let cache = fullscreenCache, cache.pid == pid,
           Date().timeIntervalSince(cache.at) < fullscreenCacheTTL {
            return cache.result
        }
        let result = computeFullscreenOrBorderless(pid: pid)
        fullscreenCache = (pid, Date(), result)
        return result
    }

    private func computeFullscreenOrBorderless(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.main else { return false }

        let screenFrame = screen.frame

        for window in list {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"] else { continue }

            // Only detect true fullscreen: window covers the entire screen frame exactly
            // (2pt tolerance for retina rounding). Maximized windows have a menu bar gap
            // and should NOT be suppressed.
            let fullWidth  = abs(w - screenFrame.width)  < 2
            let fullHeight = abs(h - screenFrame.height) < 2
            if fullWidth && fullHeight { return true }
        }

        return false
    }

    // MARK: - Installed Apps Discovery

    func startInstalledAppsQuery() {
        // Run the Spotlight scan once per app session; repeated tab visits were
        // accumulating observers and re-scanning /Applications every time.
        guard metadataQuery == nil else { return }
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
        NotificationCenter.default.removeObserver(
            self, name: .NSMetadataQueryDidFinishGathering, object: query
        )

        var apps: [InstalledApp] = []
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }

            let url = URL(fileURLWithPath: path)
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }

            let name = (item.value(forAttribute: kMDItemDisplayName as String) as? String)
                ?? url.deletingPathExtension().lastPathComponent
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
