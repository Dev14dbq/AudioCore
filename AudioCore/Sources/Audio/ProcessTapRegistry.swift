import AppKit
import CoreAudio
import Foundation

/// Wraps the modern Swift CoreAudio object graph (macOS 15+, `AudioHardwareSystem`)
/// to find processes the system can tap for audio. See
/// https://developer.apple.com/documentation/coreaudio/audiohardwaresystem
enum ProcessTapRegistry {

    struct Entry {
        let processObjectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
    }

    static func audioCapableProcesses() -> [Entry] {
        guard let processes = try? AudioHardwareSystem.shared.processes else { return [] }
        return processes.compactMap { process -> Entry? in
            guard let isOutput = try? process.isRunningOutput, isOutput else { return nil }
            guard let pid = try? process.pid else { return nil }
            let bundleID = try? process.bundleID
            return Entry(processObjectID: process.id, pid: pid, bundleID: bundleID ?? nil)
        }
    }

    /// Apps currently visible to the user that also have an audio-capable
    /// process object. Grouped by bundle ID rather than PID: Chromium/Electron
    /// apps (Chrome, Yandex Music, Electron-based players, etc.) emit audio
    /// from a per-tab/per-window helper *subprocess*, not from the app's own
    /// main PID, so `NSRunningApplication(processIdentifier:)` on that PID
    /// returns nil even though CoreAudio correctly reports the owning app's
    /// bundle ID. We must not drop those entries — only use NSRunningApplication
    /// opportunistically to get a nicer display name.
    static func controllableApps() -> [AudioAppInfo] {
        controllableApps(from: audioCapableProcesses())
    }

    /// Dedups by bundle ID (first-seen wins), excludes AudioCore's own bundle
    /// ID and empty/missing bundle IDs, and sorts by display name. Pulled out
    /// of `controllableApps()` as a pure function of `entries` so this
    /// filtering/sorting logic is unit-testable without live Core Audio state.
    static func controllableApps(from entries: [Entry], ownBundleID: String? = Bundle.main.bundleIdentifier) -> [AudioAppInfo] {
        var seen = Set<String>()
        var result: [AudioAppInfo] = []
        for entry in entries {
            guard let bundleID = entry.bundleID, !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            guard bundleID != ownBundleID else { continue }
            seen.insert(bundleID)
            result.append(AudioAppInfo(bundleID: bundleID, name: displayName(forBundleID: bundleID)))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All CoreAudio process objects currently attributed to `bundleID`. A
    /// single app can own several of these at once (e.g. one per Chrome tab
    /// that's making sound), and all of them need to go into the same tap for
    /// the app's volume control to affect all of its audio.
    static func processObjectIDs(forBundleID bundleID: String) -> [AudioObjectID] {
        audioCapableProcesses().filter { $0.bundleID == bundleID }.map(\.processObjectID)
    }

    /// Groups process object IDs by bundle ID in one pass over `entries`, so
    /// callers that need this for several bundle IDs at once (see
    /// `AudioMixerEngine.sync`) don't have to re-run `audioCapableProcesses()`
    /// once per bundle ID.
    static func processObjectIDsByBundleID(_ entries: [Entry]) -> [String: [AudioObjectID]] {
        Dictionary(grouping: entries.compactMap { entry in entry.bundleID.map { ($0, entry.processObjectID) } }, by: { $0.0 })
            .mapValues { $0.map(\.1) }
    }

    private static func displayName(forBundleID bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            if let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String { return name }
            if let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String { return name }
            if let name = bundle.localizedInfoDictionary?["CFBundleName"] as? String { return name }
            if let name = bundle.infoDictionary?["CFBundleName"] as? String { return name }
        }
        return bundleID
    }
}
