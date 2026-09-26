import SwiftUI

/// A 4-digit numeric PIN gate. Creates + confirms when no PIN exists; otherwise verifies.
struct PinView: View {
    let requireExisting: Bool
    let verify: (String) -> Bool
    let onCreate: (String) -> Void
    let onSuccess: () -> Void

    @State private var entered = ""
    @State private var firstPin: String?
    @State private var error: String?

    private var title: String {
        requireExisting ? "Enter your PIN" : (firstPin == nil ? "Create a 4-digit PIN" : "Confirm your PIN")
    }
    private var subtitle: String {
        requireExisting ? "This section is protected."
            : (firstPin == nil ? "You'll need this PIN to open the Adult section." : "Enter the same PIN again.")
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i < entered.count ? Theme.accent : Color.white.opacity(0.2))
                        .frame(width: 16, height: 16)
                }
            }
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            pad.padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    private var pad: some View {
        VStack(spacing: 14) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                HStack(spacing: 14) { ForEach(row, id: \.self) { key($0) } }
            }
            HStack(spacing: 14) {
                Color.clear.frame(width: 72, height: 72)
                key("0")
                Button { if !entered.isEmpty { entered.removeLast() } } label: {
                    Image(systemName: "delete.left").font(.title2)
                        .frame(width: 72, height: 72)
                        .background(Theme.surface).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func key(_ d: String) -> some View {
        Button { press(d) } label: {
            Text(d).font(.title.weight(.semibold))
                .frame(width: 72, height: 72)
                .background(Theme.surface).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func press(_ d: String) {
        guard entered.count < 4 else { return }
        error = nil
        entered += d
        if entered.count == 4 { submit() }
    }

    private func submit() {
        let pin = entered
        if requireExisting {
            if verify(pin) { onSuccess() } else { error = "Incorrect PIN."; entered = "" }
        } else if firstPin == nil {
            firstPin = pin; entered = ""
        } else if pin == firstPin {
            onCreate(pin)
        } else {
            error = "PINs didn't match. Try again."; firstPin = nil; entered = ""
        }
    }
}

/// PIN-gated Adult tab: Live channels + Movies, both filtered to adult content.
struct AdultView: View {
    let catalog: Catalog
    @State private var unlocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if !unlocked {
                    PinView(requireExisting: Prefs.hasAdultPin(),
                            verify: { Prefs.adultPin() == $0 },
                            onCreate: { Prefs.setAdultPin($0); unlocked = true },
                            onSuccess: { unlocked = true })
                } else {
                    List {
                        NavigationLink { AdultLiveView(catalog: catalog) } label: {
                            Label("Live Channels", systemImage: "tv")
                        }
                        NavigationLink { AdultMoviesView(catalog: catalog) } label: {
                            Label("Movies", systemImage: "film")
                        }
                    }
                    .listStyle(.plain)
                    .navigationTitle("Adult")
                }
            }
            .screenBackground()
        }
        // Re-lock when the app is backgrounded so it asks again next time.
        .onChange(of: scenePhase) { phase in if phase == .background { unlocked = false } }
    }
}

/// Adult live channels: scan every category's sections and keep the adult ones.
struct AdultLiveView: View {
    let catalog: Catalog
    @State private var sections: [LiveSection] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                Text("No adult channels.").foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.label) {
                            ForEach(section.channels) { ch in
                                NavigationLink {
                                    PlayerView(title: ch.name, url: catalog.playUrl(ch), resume: nil)
                                } label: {
                                    ChannelRow(channel: ch)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Adult · Live")
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { if sections.isEmpty { await load() } }
    }

    private func load() async {
        error = nil; loading = true
        do {
            try await catalog.loadCategories()
            let cats = catalog.categories
            var found: [LiveSection] = []
            await withTaskGroup(of: [LiveSection].self) { group in
                for c in cats {
                    group.addTask {
                        let chans = (try? await catalog.client.liveChannels(categoryId: c.id)) ?? []
                        return chans.splitSections().filter { isAdultLabel($0.label) }
                    }
                }
                for await r in group { found.append(contentsOf: r) }
            }
            sections = found
        } catch {
            self.error = "Couldn't load adult channels."
        }
        loading = false
    }
}

/// Adult movies: the "FOR ADULTS" category (or any adult category), as a poster grid.
struct AdultMoviesView: View {
    let catalog: Catalog
    @State private var movies: [Movie] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if loading {
                ProgressView().padding(40)
            } else if movies.isEmpty {
                Text("No adult movies.").foregroundStyle(Theme.muted).padding(40)
            } else {
                PosterGrid(items: movies,
                           title: { stripVodCode($0.name) },
                           poster: { $0.poster },
                           badge: { vodLangCode($0.name) }) { m in
                    MovieDetailView(catalog: catalog, movie: m)
                }
            }
        }
        .navigationTitle("Adult · Movies")
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { if movies.isEmpty { await load() } }
    }

    private func load() async {
        error = nil; loading = true
        do {
            try await catalog.loadMovieCategories()
            let adultCats = catalog.movieCategories.filter { isAdultLabel($0.name) }
            var all: [Movie] = []
            for c in adultCats { all.append(contentsOf: (try? await catalog.movies(c.id)) ?? []) }
            movies = all
        } catch {
            self.error = "Couldn't load adult movies."
        }
        loading = false
    }
}
