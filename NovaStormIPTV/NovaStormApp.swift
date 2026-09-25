import SwiftUI
import AVFoundation

@main
struct NovaStormApp: App {
    @StateObject private var session = Session()

    init() {
        // Keep audio going when the screen locks / app backgrounds (UIBackgroundModes: audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
