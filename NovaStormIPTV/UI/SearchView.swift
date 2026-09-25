import SwiftUI

private struct LangChip: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct SearchView: View {
    let catalog: Catalog
    @State private var query = ""
    @State private var results = SearchResults()
    @State private var searching = false
    @State private var lang = "All"

    /// All + each language present in the movie hits: English first, "Other" last.
    private var langChips: [LangChip] {
        var counts: [String: Int] = [:]
        for m in results.movies { counts[m.lang.ifBlank("Other"), default: 0] += 1 }
        func rank(_ k: String) -> Int { k == "English" ? 0 : (k == "Other" ? 2 : 1) }
        let ordered = counts.sorted { a, b in
            if rank(a.key) != rank(b.key) { return rank(a.key) < rank(b.key) }
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
        return [LangChip(name: "All", count: results.movies.count)]
            + ordered.map { LangChip(name: $0.key, count: $0.value) }
    }

    private var shownMovies: [Movie] {
        lang == "All" ? results.movies : results.movies.filter { $0.lang.ifBlank("Other") == lang }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if trimmed.count < 2 {
                        Text("Type at least 2 characters to search.")
                            .foregroundStyle(Theme.muted).padding(16)
                    } else if searching && results.total == 0 {
                        ProgressView().padding(16)
                    } else if results.total == 0 {
                        Text("No matches for \"\(query)\".")
                            .foregroundStyle(Theme.muted).padding(16)
                    } else {
                        if !results.movies.isEmpty {
                            header("Movies", shownMovies.count)
                            if langChips.count > 2 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(langChips) { chip in
                                            SourceChip(label: "\(chip.name)  \(chip.count)",
                                                       selected: lang == chip.name) { lang = chip.name }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            PosterGrid(items: shownMovies,
                                       title: { stripVodCode($0.name) },
                                       poster: { $0.poster },
                                       badge: { vodLangCode($0.name) }) { m in
                                MovieDetailView(catalog: catalog, movie: m)
                            }
                        }
                        if !results.series.isEmpty {
                            header("Series", results.series.count)
                            PosterGrid(items: results.series,
                                       title: { stripVodCode($0.name) },
                                       poster: { $0.poster },
                                       badge: { vodLangCode($0.name) }) { s in
                                SeriesDetailView(catalog: catalog, series: s)
                            }
                        }
                        if !results.live.isEmpty {
                            header("Live channels", results.live.count)
                            VStack(spacing: 0) {
                                ForEach(results.live) { ch in
                                    NavigationLink {
                                        PlayerView(title: ch.name, url: catalog.playUrl(ch), resume: nil)
                                    } label: {
                                        ChannelRow(channel: ch)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .screenBackground()
            .searchable(text: $query, prompt: "Channels, movies & series")
            .task(id: query) {
                let q = trimmed
                guard q.count >= 2 else {
                    results = SearchResults()
                    searching = false
                    return
                }
                searching = true
                try? await Task.sleep(nanoseconds: 300_000_000)   // debounce keystrokes
                if Task.isCancelled { return }
                results = (try? await catalog.client.search(query: q, limit: 100)) ?? SearchResults()
                lang = "All"
                searching = false
            }
        }
    }

    private func header(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.headline)
            Text("\(count)").foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
    }
}
