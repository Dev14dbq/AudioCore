import AppIntents

/// AppEntity wrapper around `AudioAppInfo` so it can be used as an AppIntent
/// parameter — this is what powers the app picker shown when the user adds
/// or edits an AudioCore control in Control Center's "Edit Controls" sheet.
struct AudioAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let defaultQuery = AudioAppEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let placeholder = AudioAppEntity(id: "", name: "Choose an App")
}

struct AudioAppEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AudioAppEntity] {
        SharedStore.knownApps
            .filter { identifiers.contains($0.bundleID) }
            .map { AudioAppEntity(id: $0.bundleID, name: $0.name) }
    }

    func suggestedEntities() async throws -> [AudioAppEntity] {
        SharedStore.knownApps.map { AudioAppEntity(id: $0.bundleID, name: $0.name) }
    }
}
