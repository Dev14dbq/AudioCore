import AppIntents

/// Backs the mute toggle control. Control Center sets `value` to the new
/// toggle state and calls `perform()`; `app` is bound ahead of time when the
/// toggle is constructed for a given control instance (see Controls.swift).
struct SetMuteIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set App Mute"

    @Parameter(title: "App")
    var app: AudioAppEntity?

    @Parameter(title: "Muted")
    var value: Bool

    init() {
        self.value = false
    }

    init(app: AudioAppEntity) {
        self.app = app
        self.value = false
    }

    func perform() async throws -> some IntentResult {
        guard let app, !app.id.isEmpty else { return .result() }
        SharedStore.shared.setMuted(value, for: app.id)
        return .result()
    }
}
