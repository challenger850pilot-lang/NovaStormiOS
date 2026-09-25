import Foundation

/// One resumable item in Continue Watching (movies & episodes only).
struct WatchItem: Codable, Identifiable, Hashable {
    var kind: String        // "movie" | "episode"
    var id: String          // stream_id (movie) or episode id
    var title: String
    var poster: String
    var container: String
    var url: String         // what to hand the player on resume
    var positionMs: Int64
    var durationMs: Int64
    var updatedAt: Int64

    /// 0...1 progress for the bar under the poster. Bogus tiny durations → 0.
    var progress: Double {
        durationMs > 10_000 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0
    }
}

/// Persists a small "Continue Watching" list in UserDefaults as JSON.
enum History {
    private static let key = "novastorm_history"
    private static let maxItems = 20
    private static let finishedFraction = 0.95

    static func load() -> [WatchItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([WatchItem].self, from: data) else { return [] }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Upsert by kind+id, newest first, drop finished items, cap the list.
    static func record(_ item: WatchItem) {
        var current = load().filter { !($0.kind == item.kind && $0.id == item.id) }
        let done = item.durationMs > 10_000
            && Double(item.positionMs) >= Double(item.durationMs) * finishedFraction
        if !done { current.insert(item, at: 0) }
        save(Array(current.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxItems)))
    }

    static func position(kind: String, id: String) -> Int64 {
        load().first { $0.kind == kind && $0.id == id }?.positionMs ?? 0
    }

    static func remove(kind: String, id: String) {
        save(load().filter { !($0.kind == kind && $0.id == id) })
    }

    private static func save(_ items: [WatchItem]) {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}
