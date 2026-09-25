import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            switch session.state {
            case .connecting:
                VStack(spacing: 16) {
                    ProgressView().tint(Theme.accent)
                    Text("Connecting to your gateway…").foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
            case .failed(let message):
                VStack(spacing: 18) {
                    Text("NovaStorm IPTV").font(.title.bold())
                    Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                    Button("Try again") { Task { await session.connect() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
            case .ready(let catalog):
                TabView {
                    LiveView(catalog: catalog)
                        .tabItem { Label("Live TV", systemImage: "tv") }
                    MoviesView(catalog: catalog)
                        .tabItem { Label("Movies", systemImage: "film") }
                    SeriesView(catalog: catalog)
                        .tabItem { Label("Series", systemImage: "play.rectangle.on.rectangle") }
                    SearchView(catalog: catalog)
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    VersionView()
                        .tabItem { Label("Version", systemImage: "info.circle") }
                }
            }
        }
        .task {
            if case .connecting = session.state { await session.connect() }
        }
    }
}
