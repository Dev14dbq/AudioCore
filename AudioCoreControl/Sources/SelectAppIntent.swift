import AppIntents

/// The per-instance configuration for every AudioCore control: which app it
/// targets. Control Center prompts the user with this when a tile is added
/// or edited (`.promptsForUserConfiguration()` on the control's configuration).
struct SelectAppIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose App"

    @Parameter(title: "App")
    var app: AudioAppEntity?
}
