import Foundation
import Testing
@testable import AudioCore

@MainActor
@Suite("VolumeManager")
struct VolumeManagerTests {
    private func makeStore() -> SharedStore {
        SharedStore(defaults: UserDefaults(suiteName: "VolumeManagerTests.\(UUID())")!, notify: {})
    }

    private func makeManager(store: SharedStore, mixer: FakeMixer, launchAtLogin: FakeLaunchAtLogin) -> VolumeManager {
        VolumeManager(store: store, mixer: mixer, launchAtLogin: launchAtLogin, startTimer: false, observeDarwinNotifications: false)
    }

    @Test func setGainUpdatesStatesAndPersists() {
        let store = makeStore()
        let manager = makeManager(store: store, mixer: FakeMixer(), launchAtLogin: FakeLaunchAtLogin())

        manager.setGain(0.5, for: "com.test.app")

        #expect(manager.states["com.test.app"]?.gain == 0.5)
        #expect(store.state(for: "com.test.app").gain == 0.5)
    }

    @Test func setMutedUpdatesStates() {
        let store = makeStore()
        let manager = makeManager(store: store, mixer: FakeMixer(), launchAtLogin: FakeLaunchAtLogin())

        manager.setMuted(true, for: "com.test.app")

        #expect(manager.states["com.test.app"]?.isMuted == true)
    }

    @Test func adjustVolumeClampsEndToEnd() {
        let store = makeStore()
        let manager = makeManager(store: store, mixer: FakeMixer(), launchAtLogin: FakeLaunchAtLogin())

        manager.adjustVolume(by: 10, for: "com.test.app")

        #expect(manager.states["com.test.app"]?.gain == 1.5)
    }

    @Test func setGainTriggersMixerSync() {
        let mixer = FakeMixer()
        let manager = makeManager(store: makeStore(), mixer: mixer, launchAtLogin: FakeLaunchAtLogin())
        let syncCountAtInit = mixer.syncCallCount

        manager.setGain(0.5, for: "com.test.app")

        #expect(mixer.syncCallCount == syncCountAtInit + 1)
    }

    @Test func launchAtLoginRegisteredOnceAtInit() {
        let fakeLaunchAtLogin = FakeLaunchAtLogin()
        _ = makeManager(store: makeStore(), mixer: FakeMixer(), launchAtLogin: fakeLaunchAtLogin)

        #expect(fakeLaunchAtLogin.registerCalls == 1)
    }

    @Test func refreshDoesNotCrashWithoutLiveCoreAudioState() {
        let manager = makeManager(store: makeStore(), mixer: FakeMixer(), launchAtLogin: FakeLaunchAtLogin())
        // No crash is the assertion here — discovered-app content depends on
        // the live Core Audio process list, which this pass doesn't mock.
        manager.refresh()
    }
}

private final class FakeMixer: AudioMixing {
    private(set) var syncCallCount = 0
    private(set) var setGainCalls: [(gain: Float, isMuted: Bool, bundleID: String)] = []
    private(set) var primeCallCount = 0
    var permissionWarningDetected = false

    func setGain(_ gain: Float, isMuted: Bool, for bundleID: String) {
        setGainCalls.append((gain, isMuted, bundleID))
    }

    func sync(activeBundleIDs: Set<String>, initialState: (String) -> (gain: Float, isMuted: Bool)) {
        syncCallCount += 1
    }

    func stopAll() {}

    func primeAudioCapturePermission() {
        primeCallCount += 1
    }
}

private final class FakeLaunchAtLogin: LaunchAtLoginRegistering {
    private(set) var registerCalls = 0
    func registerIfNeeded() { registerCalls += 1 }
}
