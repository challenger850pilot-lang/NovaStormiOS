import SwiftUI

struct SeriesView: View {
    let catalog: Catalog
    @State private var countries: [VodCountry] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let e = error {
                    ErrorRetry(message: e) { Task { await load() } }
                } else if countries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(countries) { country in
                        NavigationLink {
                            VodCategoryListView(catalog: catalog, country: country, kind: .series)
                        } label: {
                            CountryRow(country: country)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Series")
            .screenBackground()
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            try await catalog.loadSeriesCategories()
            countries = catalog.seriesCategories.groupByCountry()
        } catch {
            self.error = "Couldn't load series: \(error.localizedDescription)"
        }
    }
}

struct SeriesGridView: View {
    let catalog: Catalog
    let category: Category
    let title: String
    @State private var items: [Series] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if items.isEmpty {
                ProgressView().padding(40)
            } else {
                PosterGrid(items: items,
                           title: { stripVodCode($0.name) },
                           poster: { $0.poster },
                           badge: { vodLangCode($0.name) }) { s in
                    SeriesDetailView(catalog: catalog, series: s)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            items = try await catalog.seriesList(category.id)
        } catch {
            self.error = "Couldn't load \(title): \(error.localizedDescription)"
        }
    }
}

struct SeriesDetailView: View {
    let catalog: Catalog
    let series: Series
    @State private var seasons: [Int: [Episode]] = [:]
    @State private var season: Int = 0
    @State private var error: String?

    private var title: String { stripVodCode(series.name) }
    private var seasonNumbers: [Int] { seasons.keys.sorted() }
    private var episodes: [Episode] { seasons[season] ?? [] }

    var body: some View {
        List {
            if !series.plot.isBlank {
                Text(series.plot).font(.body).foregroundStyle(Theme.muted)
            }
            if seasonNumbers.count > 1 {
                Picker("Season", selection: $season) {
                    ForEach(seasonNumbers, id: \.self) { n in
                        Text("Season \(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
            }
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if seasons.isEmpty {
                ProgressView()
            } else {
                ForEach(episodes) { ep in
                    NavigationLink {
                        EpisodePlayer(catalog: catalog, series: series, episode: ep, title: title)
                    } label: {
                        HStack {
                            Text("E\(ep.episodeNum)")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44, alignment: .leading)
                            Text(ep.title).lineLimit(2)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            seasons = try await catalog.episodes(series.seriesId)
            season = seasonNumbers.first ?? 0
        } catch {
            self.error = "Couldn't load episodes: \(error.localizedDescription)"
        }
    }
}

/// Builds the player for an episode, including its Continue Watching entry.
struct EpisodePlayer: View {
    let catalog: Catalog
    let series: Series
    let episode: Episode
    let title: String

    var body: some View {
        let url = catalog.client.playbackUrl(episode: episode)
        let item = WatchItem(kind: "episode", id: episode.id, title: episode.title,
                             poster: episode.icon.ifBlank(series.poster), container: episode.container,
                             url: url, positionMs: 0, durationMs: 0, updatedAt: 0)
        PlayerView(title: "\(title) · S\(episode.season)E\(episode.episodeNum)", url: url, resume: item)
    }
}
