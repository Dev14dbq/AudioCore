import Foundation

enum AppGroup {
    static let identifier = "group.com.audiocore.app"

    // `UserDefaults` isn't marked `Sendable` in the SDK but is documented as
    // thread-safe internally, so caching one shared instance (instead of the
    // previous computed property that reconstructed it on every access) is
    // safe — `nonisolated(unsafe)` asserts that external synchronization
    // rather than the compiler is what makes this sound.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

/// Posted (via Darwin notification center, which works across process/sandbox
/// boundaries unlike NotificationCenter.default) whenever the Control Center
/// extension writes a new desired volume/mute state that the main app's audio
/// engine needs to pick up and apply to the live Core Audio tap.
enum DarwinNotification {
    static let volumeStateChanged = "com.audiocore.app.volumeStateChanged"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    static func observe(_ name: String, _ handler: @escaping () -> Void) -> DarwinObserverToken {
        DarwinObserverToken(name: name, handler: handler)
    }
}

/// Owns the lifetime of a Darwin notification observation; deregisters on deinit.
final class DarwinObserverToken {
    private let name: String
    private let handler: () -> Void

    fileprivate init(name: String, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<DarwinObserverToken>.fromOpaque(observer).takeUnretainedValue().handler()
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(name as CFString), nil)
    }
}
