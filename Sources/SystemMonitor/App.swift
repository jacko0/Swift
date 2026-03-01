import SwiftUI

@main
struct SystemMonitorApp: App {
    @StateObject private var stats = SystemStats()

    var body: some Scene {
        WindowGroup("System Monitor") {
            ContentView()
                .environmentObject(stats)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 190, height: 270)
    }
}
