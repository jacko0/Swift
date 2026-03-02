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
        .defaultSize(width: 700, height: 500)
    }
}

