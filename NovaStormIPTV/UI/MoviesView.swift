import SwiftUI

struct MoviesView: View {
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
                            VodCategoryListView(catalog: catalog, country: country, kind: .movies)
                        } label: {
                            CountryRow(country: country)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Movies")
            .screenBackground()
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            try await catalog.loadMovieCategories()
            countries = catalog.movieCategories.groupByCountry()
        } catch {
            self.error = "Couldn't load movies: \(error.localizedDescription)"
        }
    }
}

enum VodKind {
    case movies
    case series
}

/// The categories inside one country folder (shared by Movies and Series).
struct VodCategoryListView: View {
    let catalog: Catalog
    let country: VodCountry
    let kind: VodKind

    var body: some View {
        List(country.categories) { entry in
            NavigationLink(entry.label) {
                switch kind {
                case .movies:
                    MovieGridView(catalog: catalog, category: entry.category, title: entry.label)
                case .series:
                    SeriesGridView(catalog: catalog, category: entry.category, title: entry.label)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
    }
}

struct MovieGridView: View {
    let catalog: Catalog
    let category: Category
    let title: String
    @State private var movies: [Movie] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if movies.isEmpty {
                ProgressView().padding(40)
            } else {
                PosterGrid(items: movies,
                           title: { stripVodCode($0.name) },
                           poster: { $0.poster },
                           badge: { vodLangCode($0.name) }) { m in
                    MovieDetailView(catalog: catalog, movie: m)
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
            movies = try await catalog.movies(category.id)
        } catch {
            self.error = "Couldn't load \(title): \(error.localizedDescription)"
        }
    }
}

struct MovieDetailView: View {
    let catalog: Catalog
    let movie: Movie
    @State private var info: MovieInfo?
    @State private var sources: [MovieSource] = []
    @State private var chosen: MovieSource?

    private var title: String { stripVodCode(movie.name) }

    private var backdropUrl: URL? {
        let b = (info?.backdrop ?? "").ifBlank(movie.poster)
        return b.isBlank ? nil : URL(string: b)
    }

    private var metaLine: String {
        guard let i = info else { return "" }
        var parts: [String] = []
        if !i.year.isBlank { parts.append(i.year) }
        if !i.rating.isBlank { parts.append("★ \(i.rating)") }
        if !i.duration.isBlank { parts.append(i.duration) }
        if !i.genre.isBlank { parts.append(i.genre) }
        return parts.joined(separator: "  •  ")
    }

    private var playUrl: String {
        if let s = chosen { return catalog.client.playbackUrl(source: s) }
        return catalog.client.playbackUrl(movie: movie)
    }

    private var resumeItem: WatchItem {
        WatchItem(kind: "movie", id: String(chosen?.streamId ?? movie.streamId), title: title,
                  poster: movie.poster, container: chosen?.container ?? movie.container,
                  url: playUrl, positionMs: 0, durationMs: 0, updatedAt: 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let u = backdropUrl {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Color.black.opacity(0.3)
                        }
                    }
                    .frame(height: 220)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.title2.bold())
                    if !metaLine.isEmpty {
                        Text(metaLine).font(.subheadline).foregroundStyle(Theme.accent)
                    }
                    if let p = info?.plot, !p.isBlank {
                        Text(p).font(.body).foregroundStyle(Theme.muted)
                    }
                    if let c = info?.cast, !c.isBlank {
                        Text("Cast: \(c)").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if sources.count > 1 {
                        Text("Sources").font(.headline).padding(.top, 6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sources) { s in
                                    SourceChip(label: s.label.ifBlank(s.lang.ifBlank("Source")),
                                               selected: chosen?.id == s.id) { chosen = s }
                                }
                            }
                        }
                    }
                    NavigationLink {
                        PlayerView(title: title, url: playUrl, resume: resumeItem)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task {
            info = try? await catalog.client.vodInfo(vodId: movie.streamId)
            sources = (try? await catalog.client.movieVersions(name: movie.name)) ?? []
            chosen = sources.first { $0.streamId == movie.streamId } ?? sources.first
        }
    }
}

struct SourceChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Theme.accent : Theme.surface)
                .foregroundStyle(selected ? Color.black : Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
