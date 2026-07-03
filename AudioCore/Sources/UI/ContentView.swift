import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: VolumeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AudioCore").font(.headline)

            if manager.needsAudioCapturePermission {
                PermissionWarningBanner()
            }

            if manager.apps.isEmpty {
                Text("No apps are currently playing audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 14) {
                    ForEach(manager.apps) { app in
                        AppVolumeRow(app: app)
                    }
                }
            }

            Divider()

            Button("Quit AudioCore") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Shown when the render callback detects a tapped app going silent far
/// longer than plausible for real audio — see
/// `AggregateMixerDevice.permissionWarningDetected`. Without this, a missing
/// or revoked System Audio Recording permission looks exactly like silent,
/// unexplained breakage: sliders move, nothing happens.
private struct PermissionWarningBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System audio access needed")
                .font(.callout.bold())
            Text("AudioCore can't hear the apps it's controlling. Grant System Audio Recording access, then reopen the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Privacy & Security Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppVolumeRow: View {
    @EnvironmentObject var manager: VolumeManager
    let app: AudioAppInfo

    private var state: AppVolumeState { manager.states[app.bundleID] ?? .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(app.name)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(state.gain * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { state.gain },
                    set: { manager.setGain($0, for: app.bundleID) }
                ),
                in: 0...1.5
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(VolumeManager())
}
