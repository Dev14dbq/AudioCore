import AppIntents

/// Backs the volume up/down buttons. `delta` is baked into the intent
/// instance per control (+0.1 for the up tile, -0.1 for the down tile), so
/// tapping the Control Center tile just needs to invoke `perform()`.
struct AdjustVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust App Volume"

    @Parameter(title: "App")
    var app: AudioAppEntity?

    @Parameter(title: "Delta")
    var delta: Double

    init() {
        self.delta = 0
    }

    init(app: AudioAppEntity, delta: Double) {
        self.app = app
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        guard let app, !app.id.isEmpty else { return .result() }
        SharedStore.shared.adjustGain(by: delta, for: app.id)
        SharedStore.shared.setMuted(false, for: app.id)
        return .result()
    }
}
