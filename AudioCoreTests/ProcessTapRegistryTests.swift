import CoreAudio
import Testing
@testable import AudioCore

@Suite("ProcessTapRegistry")
struct ProcessTapRegistryTests {
    private func entry(_ objectID: UInt32, pid: Int32 = 100, bundleID: String?) -> ProcessTapRegistry.Entry {
        ProcessTapRegistry.Entry(processObjectID: AudioObjectID(objectID), pid: pid_t(pid), bundleID: bundleID)
    }

    @Test func controllableAppsDedupsByBundleID() {
        let entries = [
            entry(1, bundleID: "com.example.app"),
            entry(2, bundleID: "com.example.app")
        ]
        let result = ProcessTapRegistry.controllableApps(from: entries, ownBundleID: nil)
        #expect(result.map(\.bundleID) == ["com.example.app"])
    }

    @Test func controllableAppsExcludesOwnBundleID() {
        let entries = [
            entry(1, bundleID: "com.audiocore.app"),
            entry(2, bundleID: "com.other.app")
        ]
        let result = ProcessTapRegistry.controllableApps(from: entries, ownBundleID: "com.audiocore.app")
        #expect(result.map(\.bundleID) == ["com.other.app"])
    }

    @Test func controllableAppsExcludesEmptyOrNilBundleID() {
        let entries = [
            entry(1, bundleID: ""),
            entry(2, bundleID: nil),
            entry(3, bundleID: "com.other.app")
        ]
        let result = ProcessTapRegistry.controllableApps(from: entries, ownBundleID: nil)
        #expect(result.map(\.bundleID) == ["com.other.app"])
    }

    @Test func controllableAppsSortsCaseInsensitively() {
        // These bundle IDs don't resolve to a running/installed app on the
        // test runner, so `displayName(forBundleID:)` falls back to the
        // bundle ID string itself — deterministic and directly sortable.
        let entries = [
            entry(1, bundleID: "Zebra.nonexistent.app"),
            entry(2, bundleID: "apple.nonexistent.app"),
            entry(3, bundleID: "banana.nonexistent.app")
        ]
        let result = ProcessTapRegistry.controllableApps(from: entries, ownBundleID: nil)
        #expect(result.map(\.bundleID) == ["apple.nonexistent.app", "banana.nonexistent.app", "Zebra.nonexistent.app"])
    }

    @Test func processObjectIDsByBundleIDGroupsCorrectly() {
        let entries = [
            entry(1, bundleID: "com.example.app"),
            entry(2, bundleID: "com.example.app"),
            entry(3, bundleID: "com.other.app"),
            entry(4, bundleID: nil)
        ]
        let grouped = ProcessTapRegistry.processObjectIDsByBundleID(entries)
        #expect(Set(grouped["com.example.app"] ?? []) == Set([AudioObjectID(1), AudioObjectID(2)]))
        #expect(grouped["com.other.app"] == [AudioObjectID(3)])
        #expect(grouped.count == 2)
    }
}
