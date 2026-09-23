import SwiftUI

@main
@MainActor
struct DeviceProbeApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HealthProbeView(model: HealthProbeModel(service: LiveHealthProbeService()))
            }
        }
    }
}