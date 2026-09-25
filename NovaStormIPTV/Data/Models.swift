import Foundation

/// Gateway login. `base` is the normalized root, e.g. http://host:port with no trailing slash.
struct XtreamAuth: Codable, Equatable {
    var baseUrl: String
    var username: String
    var password: String

    var base: String {
        var b = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = b.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { b = "http://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }
}

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
}

struct LiveChannel: Identifiable, Hashable {
    let streamId: Int
    let name: String
    let icon: String
    let categoryId: String
    let epgId: String
    var id: Int { streamId }
}

struct Movie: Identifiable, Hashable {
    let streamId: Int
    let name: String
    let poster: String
    let categoryId: String
    let container: String
    let rating: String
    var lang: String = ""
    var year: String = ""
    var id: Int { streamId }
}

struct MovieInfo {
    let plot: String
    let cast: String
    let director: String
    let genre: String
    let year: String
    let rating: String
    let duration: String
    let backdrop: String
    let poster: String
    let container: String
}

struct Series: Identifiable, Hashable {
    let seriesId: Int
    let name: String
    let poster: String
    let categoryId: String
    let plot: String
    let cast: String
    let genre: String
    let rating: String
    var id: Int { seriesId }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let title: String
    let season: Int
    let episodeNum: Int
    let container: String
    let icon: String
}

struct Actor: Identifiable, Hashable {
    let name: String
    let photo: String
    let count: Int
    var id: String { name }
}

struct LangCount: Hashable {
    let name: String
    let count: Int
}

struct ActorDetail {
    let name: String
    let photo: String
    let count: Int
    let languages: [LangCount]
    let movies: [Movie]
}

/// One playable source of a film (the gateway groups languages/qualities under one poster).
struct MovieSource: Identifiable, Hashable {
    let streamId: Int
    let name: String
    let poster: String
    let container: String
    let label: String
    let lang: String
    var id: Int { streamId }
}

struct SearchResults {
    var live: [LiveChannel] = []
    var movies: [Movie] = []
    var series: [Series] = []
    var total: Int { live.count + movies.count + series.count }
}

struct EpgEntry {
    let title: String
    let start: String
    let end: String
    let description: String
    let startMs: Int64
    let endMs: Int64
}

extension String {
    /// Kotlin's ifBlank: this string, or the fallback when it's empty/whitespace.
    func ifBlank(_ fallback: @autoclosure () -> String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback() : self
    }
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
