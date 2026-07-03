import SwiftUI

@main
struct AudioCoreApp: App {
    @StateObject private var manager = VolumeManager()

    var body: some Scene {
        MenuBarExtra("AudioCore", systemImage: "speaker.wave.2.circle.fill") {
            ContentView()
                .environmentObject(manager)
        }
        .menuBarExtraStyle(.window)
    }
}
