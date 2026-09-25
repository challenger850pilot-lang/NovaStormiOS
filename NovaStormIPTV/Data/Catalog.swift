import Foundation

/// The connected client plus lazily cached per-category lists.
final class Catalog {
    let client: XtreamClient
    init(client: XtreamClient) { self.client = client }

    // MARK: Live — the gateway's categories are plain country names; sub-folders come
    // from "#### … ####" divider rows inside each channel list.

    private(set) var categories: [Category] = []
    private var channelCache: [String: [LiveChannel]] = [:]

    func loadCategories() async throws {
        if categories.isEmpty { categories = try await client.liveCategories() }
    }

    func channels(_ categoryId: String) async throws -> [LiveChannel] {
        if let c = channelCache[categoryId] { return c }
        let list = try await client.liveChannels(categoryId: categoryId)
        channelCache[categoryId] = list
        return list
    }

    func sections(_ categoryId: String) async throws -> [LiveSection] {
        try await channels(categoryId).splitSections()
    }

    func playUrl(_ channel: LiveChannel) -> String { client.liveUrl(streamId: channel.streamId) }

    // MARK: Movies

    private(set) var movieCategories: [Category] = []
    private var movieCache: [String: [Movie]] = [:]

    func loadMovieCategories() async throws {
        if movieCategories.isEmpty { movieCategories = try await client.vodCategories() }
    }

    func movies(_ categoryId: String) async throws -> [Movie] {
        if let c = movieCache[categoryId] { return c }
        let list = try await client.vodStreams(categoryId: categoryId)
        movieCache[categoryId] = list
        return list
    }

    // MARK: Series

    private(set) var seriesCategories: [Category] = []
    private var seriesCache: [String: [Series]] = [:]

    func loadSeriesCategories() async throws {
        if seriesCategories.isEmpty { seriesCategories = try await client.seriesCategories() }
    }

    func seriesList(_ categoryId: String) async throws -> [Series] {
        if let c = seriesCache[categoryId] { return c }
        let list = try await client.series(categoryId: categoryId)
        seriesCache[categoryId] = list
        return list
    }

    func episodes(_ seriesId: Int) async throws -> [Int: [Episode]] {
        try await client.seriesInfo(seriesId: seriesId)
    }

    // MARK: EPG (now playing)

    private var epgCache: [Int: String] = [:]

    func nowPlaying(_ streamId: Int) async -> String {
        if let t = epgCache[streamId] { return t }
        let text = (try? await client.shortEpg(streamId: streamId, limit: 1).first?.title) ?? ""
        epgCache[streamId] = text
        return text
    }
}
