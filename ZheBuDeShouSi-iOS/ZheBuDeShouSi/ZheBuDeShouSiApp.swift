import SwiftUI

@main
struct ZheBuDeShouSiApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var healthStore = HealthStore()
    @StateObject private var healthSync = HealthSyncCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(healthStore)
                .environmentObject(healthSync)
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 860)
        #endif
    }
}
