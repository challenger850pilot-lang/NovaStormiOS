import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on non-Apple platforms (local type-checks)
#endif

enum XtreamError: Error, LocalizedError {
    case badUrl(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badUrl(let u): return "Bad URL: \(u)"
        case .http(let c): return "Gateway replied \(c)"
        }
    }
}

/// Talks to the RV IPTV Gateway: the Xtream-compatible player_api plus the gateway's own
/// /api endpoints (search, actors, versions) and its MKV → HLS remux for Apple players.
final class XtreamClient {
    let auth: XtreamAuth
    var base: String { auth.base }
    private let session: URLSession

    init(auth: XtreamAuth) {
        self.auth = auth
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 180
        session = URLSession(configuration: cfg)
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: XtreamClient.unreserved) ?? s
    }

    private func apiUrl(_ action: String?, _ extra: [String: String] = [:]) -> String {
        var s = "\(base)/player_api.php?username=\(enc(auth.username))&password=\(enc(auth.password))"
        if let a = action { s += "&action=\(a)" }
        for (k, v) in extra { s += "&\(k)=\(enc(v))" }
        return s
    }

    private func getData(_ url: String) async throws -> Data {
        guard let u = URL(string: url) else { throw XtreamError.badUrl(url) }
        var req = URLRequest(url: u)
        req.setValue("NovaStorm IPTV iOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw XtreamError.http(h.statusCode)
        }
        return data
    }

    private func getJSON(_ url: String) async throws -> Any {
        try JObj.parse(try await getData(url))
    }

    // MARK: - Auth

    func authenticate() async -> Bool {
        guard let any = try? await getJSON(apiUrl(nil)) else { return false }
        let info = JObj.object(any).obj("user_info") ?? JObj([:])
        return info.i("auth") == 1 || info.s("auth") == "1" || info.s("status").lowercased() == "active"
    }

    // MARK: - Live

    func liveCategories() async throws -> [Category] {
        JObj.objects(try await getJSON(apiUrl("get_live_categories"))).map {
            Category(id: $0.s("category_id"), name: $0.s("category_name"))
        }
    }

    func liveChannels(categoryId: String? = nil) async throws -> [LiveChannel] {
        var extra: [String: String] = [:]
        if let c = categoryId { extra["category_id"] = c }
        return JObj.objects(try await getJSON(apiUrl("get_live_streams", extra))).map {
            LiveChannel(streamId: $0.i("stream_id"), name: $0.s("name"), icon: $0.s("stream_icon"),
                        categoryId: $0.s("category_id"), epgId: $0.s("epg_channel_id"))
        }
    }

    func liveUrl(streamId: Int, ext: String = "m3u8") -> String {
        "\(base)/live/\(enc(auth.username))/\(enc(auth.password))/\(streamId).\(ext)"
    }

    // MARK: - Movies

    func vodCategories() async throws -> [Category] {
        JObj.objects(try await getJSON(apiUrl("get_vod_categories"))).map {
            Category(id: $0.s("category_id"), name: $0.s("category_name"))
        }
    }

    func vodStreams(categoryId: String? = nil) async throws -> [Movie] {
        var extra: [String: String] = [:]
        if let c = categoryId { extra["category_id"] = c }
        return JObj.objects(try await getJSON(apiUrl("get_vod_streams", extra))).map {
            Movie(streamId: $0.i("stream_id"), name: $0.s("name"), poster: $0.s("stream_icon"),
                  categoryId: $0.s("category_id"), container: $0.s("container_extension", "mp4"),
                  rating: $0.s("rating"))
        }
    }

    func movieUrl(streamId: Int, container: String) -> String {
        "\(base)/movie/\(enc(auth.username))/\(enc(auth.password))/\(streamId).\(container.ifBlank("mp4"))"
    }

    /// AVPlayer can't open MKV/AVI; the gateway remuxes those to fMP4 HLS on first request.
    func hlsVodUrl(kind: String, streamRef: String) -> String {
        "\(base)/hlsvod/\(enc(auth.username))/\(enc(auth.password))/\(kind)/\(streamRef)/index.m3u8"
    }

    static func needsRemux(container: String) -> Bool {
        !["mp4", "m4v", "mov"].contains(container.lowercased())
    }

    func playbackUrl(movie: Movie) -> String {
        let c = movie.container.ifBlank("mp4")
        return XtreamClient.needsRemux(container: c)
            ? hlsVodUrl(kind: "movie", streamRef: "\(movie.streamId).\(c)")
            : movieUrl(streamId: movie.streamId, container: c)
    }

    func playbackUrl(source: MovieSource) -> String {
        let c = source.container.ifBlank("mp4")
        return XtreamClient.needsRemux(container: c)
            ? hlsVodUrl(kind: "movie", streamRef: "\(source.streamId).\(c)")
            : movieUrl(streamId: source.streamId, container: c)
    }

    func playbackUrl(episode: Episode) -> String {
        let c = episode.container.ifBlank("mp4")
        return XtreamClient.needsRemux(container: c)
            ? hlsVodUrl(kind: "series", streamRef: "\(episode.id).\(c)")
            : episodeUrl(episodeId: episode.id, container: c)
    }

    func vodInfo(vodId: Int) async throws -> MovieInfo {
        let obj = JObj.object(try await getJSON(apiUrl("get_vod_info", ["vod_id": String(vodId)])))
        let info = obj.obj("info") ?? JObj([:])
        let md = obj.obj("movie_data") ?? JObj([:])
        let backdrops = info.strArr("backdrop_path")
        return MovieInfo(
            plot: info.s("plot").ifBlank(info.s("description")),
            cast: info.s("cast").ifBlank(info.s("actors")),
            director: info.s("director"),
            genre: info.s("genre"),
            year: String(info.s("releasedate").prefix(4)).ifBlank(info.s("year")),
            rating: info.s("rating"),
            duration: info.s("duration"),
            backdrop: backdrops.first ?? info.s("movie_image"),
            poster: info.s("movie_image"),
            container: md.s("container_extension", "mp4"))
    }

    // MARK: - Gateway extras (search index, actors, versions)

    func actors(query: String = "", limit: Int = 200) async throws -> [Actor] {
        JObj.objects(try await getJSON("\(base)/api/actors?q=\(enc(query))&limit=\(limit)")).map {
            Actor(name: $0.s("name"), photo: $0.s("photo"), count: $0.i("count"))
        }
    }

    func movieVersions(name: String) async throws -> [MovieSource] {
        JObj.objects(try await getJSON("\(base)/api/versions?name=\(enc(name))")).map {
            MovieSource(streamId: $0.i("stream_id"), name: $0.s("name"), poster: $0.s("poster"),
                        container: $0.s("container", "mp4"), label: $0.s("label"), lang: $0.s("lang"))
        }
    }

    func actorDetail(name: String) async throws -> ActorDetail {
        let obj = JObj.object(try await getJSON("\(base)/api/actor?name=\(enc(name))"))
        let langs = obj.arr("languages").map { LangCount(name: $0.s("name"), count: $0.i("count")) }
        let movies = obj.arr("movies").map {
            Movie(streamId: $0.i("stream_id"), name: $0.s("name"), poster: $0.s("poster"),
                  categoryId: "", container: $0.s("container", "mp4"), rating: "",
                  lang: $0.s("lang"), year: $0.s("year"))
        }
        return ActorDetail(name: obj.s("name", name), photo: obj.s("photo"),
                           count: obj.i("count", movies.count), languages: langs, movies: movies)
    }

    func search(query: String, limit: Int = 100) async throws -> SearchResults {
        let obj = JObj.object(try await getJSON("\(base)/api/search?q=\(enc(query))&limit=\(limit)"))
        var r = SearchResults()
        r.movies = obj.arr("movies").map {
            Movie(streamId: $0.i("stream_id"), name: $0.s("name"), poster: $0.s("poster"),
                  categoryId: $0.s("category_id"), container: $0.s("container", "mp4"),
                  rating: $0.s("rating"), lang: $0.s("lang"))
        }
        r.series = obj.arr("series").map {
            Series(seriesId: $0.i("series_id"), name: $0.s("name"), poster: $0.s("poster"),
                   categoryId: $0.s("category_id"), plot: "", cast: "", genre: "", rating: "")
        }
        r.live = obj.arr("live").map {
            LiveChannel(streamId: $0.i("stream_id"), name: $0.s("name"), icon: $0.s("icon"),
                        categoryId: $0.s("category_id"), epgId: $0.s("epg_channel_id"))
        }
        return r
    }

    // MARK: - Series

    func seriesCategories() async throws -> [Category] {
        JObj.objects(try await getJSON(apiUrl("get_series_categories"))).map {
            Category(id: $0.s("category_id"), name: $0.s("category_name"))
        }
    }

    func series(categoryId: String? = nil) async throws -> [Series] {
        var extra: [String: String] = [:]
        if let c = categoryId { extra["category_id"] = c }
        return JObj.objects(try await getJSON(apiUrl("get_series", extra))).map {
            Series(seriesId: $0.i("series_id"), name: $0.s("name"), poster: $0.s("cover"),
                   categoryId: $0.s("category_id"), plot: $0.s("plot"), cast: $0.s("cast"),
                   genre: $0.s("genre"), rating: $0.s("rating"))
        }
    }

    /// Season number → episodes, in episode order.
    func seriesInfo(seriesId: Int) async throws -> [Int: [Episode]] {
        let obj = JObj.object(try await getJSON(apiUrl("get_series_info", ["series_id": String(seriesId)])))
        var out: [Int: [Episode]] = [:]
        for (seasonKey, value) in obj.dict("episodes") {
            let season = Int(seasonKey) ?? 0
            let eps = JObj.objects(value).map { e -> Episode in
                Episode(id: e.s("id"),
                        title: e.s("title").ifBlank("Episode \(e.s("episode_num"))"),
                        season: e.i("season", season),
                        episodeNum: e.i("episode_num"),
                        container: e.s("container_extension", "mp4"),
                        icon: e.obj("info")?.s("movie_image") ?? "")
            }.sorted { $0.episodeNum < $1.episodeNum }
            out[season] = eps
        }
        return out
    }

    func episodeUrl(episodeId: String, container: String) -> String {
        "\(base)/series/\(enc(auth.username))/\(enc(auth.password))/\(episodeId).\(container.ifBlank("mp4"))"
    }

    // MARK: - EPG

    private func b64(_ s: String) -> String {
        guard let d = Data(base64Encoded: s), let t = String(data: d, encoding: .utf8) else { return s }
        return t
    }

    func shortEpg(streamId: Int, limit: Int = 4) async throws -> [EpgEntry] {
        let obj = JObj.object(try await getJSON(
            apiUrl("get_short_epg", ["stream_id": String(streamId), "limit": String(limit)])))
        return obj.arr("epg_listings").map {
            EpgEntry(title: b64($0.s("title")), start: $0.s("start"), end: $0.s("end"),
                     description: b64($0.s("description")),
                     startMs: $0.l("start_timestamp") * 1000, endMs: $0.l("stop_timestamp") * 1000)
        }
    }
}
