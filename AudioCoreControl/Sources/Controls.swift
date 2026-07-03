import AppIntents
import SwiftUI
import WidgetKit

struct MuteControlValue {
    let app: AudioAppEntity
    let isMuted: Bool
}

struct MuteValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectAppIntent) -> MuteControlValue {
        MuteControlValue(app: configuration.app ?? .placeholder, isMuted: false)
    }

    func currentValue(configuration: SelectAppIntent) async throws -> MuteControlValue {
        let app = configuration.app ?? .placeholder
        let state = SharedStore.state(for: app.id)
        return MuteControlValue(app: app, isMuted: state.isMuted)
    }
}

/// A Control Center toggle: mutes/unmutes whichever app the user picks when
/// they add this control. Users can add several instances, one per app.
struct MuteControl: ControlWidget {
    static let kind = "com.audiocore.app.control.mute"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: MuteValueProvider()) { value in
            ControlWidgetToggle(isOn: value.isMuted, action: SetMuteIntent(app: value.app)) {
                Label(value.app.name, systemImage: value.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
        }
        .displayName("AudioCore: Mute")
        .description("Mute or unmute one app's audio.")
        .promptsForUserConfiguration()
    }
}

struct VolumeStepControlValue {
    let app: AudioAppEntity
    let percent: Int
}

struct VolumeStepValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectAppIntent) -> VolumeStepControlValue {
        VolumeStepControlValue(app: configuration.app ?? .placeholder, percent: 100)
    }

    func currentValue(configuration: SelectAppIntent) async throws -> VolumeStepControlValue {
        let app = configuration.app ?? .placeholder
        let state = SharedStore.state(for: app.id)
        return VolumeStepControlValue(app: app, percent: Int((state.gain * 100).rounded()))
    }
}

/// Raises the target app's volume by 10 percentage points per tap.
struct VolumeUpControl: ControlWidget {
    static let kind = "com.audiocore.app.control.volumeUp"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: VolumeStepValueProvider()) { value in
            ControlWidgetButton(action: AdjustVolumeIntent(app: value.app, delta: 0.1)) {
                Label("\(value.app.name) +10%", systemImage: "speaker.wave.3.fill")
            }
        }
        .displayName("AudioCore: Volume Up")
        .description("Raise one app's volume by 10%.")
        .promptsForUserConfiguration()
    }
}

/// Lowers the target app's volume by 10 percentage points per tap.
struct VolumeDownControl: ControlWidget {
    static let kind = "com.audiocore.app.control.volumeDown"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: VolumeStepValueProvider()) { value in
            ControlWidgetButton(action: AdjustVolumeIntent(app: value.app, delta: -0.1)) {
                Label("\(value.app.name) −10%", systemImage: "speaker.wave.1.fill")
            }
        }
        .displayName("AudioCore: Volume Down")
        .description("Lower one app's volume by 10%.")
        .promptsForUserConfiguration()
    }
}
