import ServiceManagement

protocol LaunchAtLoginRegistering {
    func registerIfNeeded()
}

/// Registers AudioCore to launch at login via `SMAppService`, a no-op if
/// already registered.
struct LaunchAtLoginService: LaunchAtLoginRegistering {
    static let shared = LaunchAtLoginService()

    func registerIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }
}
