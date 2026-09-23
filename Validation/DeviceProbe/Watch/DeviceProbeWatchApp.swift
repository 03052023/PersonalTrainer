import SwiftUI

@main
@MainActor
struct DeviceProbeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HealthProbeView(model: HealthProbeModel(service: LiveHealthProbeService()))
            }
        }
    }
}