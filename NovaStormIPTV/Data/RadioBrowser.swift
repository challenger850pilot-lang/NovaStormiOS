import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A country as Radio Browser lists it (ISO 3166-1 code drives the flag).
struct RadioCountry: Identifiable, Hashable {
    let name: String
    let code: String
    let count: Int
    var id: String { code }
}

/// A playable radio station. `url` is the resolved, directly-playable stream.
struct RadioStation: Identifiable, Hashable {
    let name: String
    let url: String
    let favicon: String
    let tags: String
    let codec: String
    let bitrate: Int
    var id: String { url }

    /// codec · bitrate · first tag — the row subtitle.
    var subtitle: String {
        var parts: [String] = []
        if !codec.isBlank { parts.append(codec) }
        if bitrate > 0 { parts.append("\(bitrate)kbps") }
        if let first = tags.split(separator: ",").first {
            let t = first.trimmingCharacters(in: .whitespaces)
            if !t.isBlank { parts.append(t) }
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Radio Browser (https://api.radio-browser.info) — free, open community radio directory.
/// No key; an identifying User-Agent is expected. Mirrors are tried in turn.
enum RadioBrowser {
    private static let mirrors = [
        "https://de1.api.radio-browser.info",
        "https://nl1.api.radio-browser.info",
        "https://at1.api.radio-browser.info",
        "https://all.api.radio-browser.info",
    ]
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        return URLSession(configuration: cfg)
    }()

    private static func get(_ path: String) async throws -> Any {
        var lastErr: Error = XtreamError.http(0)
        for base in mirrors {
            guard let u = URL(string: base + path) else { continue }
            var req = URLRequest(url: u)
            req.setValue("NovaStormIPTV/1.0 (+https://nvonelaunch.com)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await session.data(for: req)
                if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    lastErr = XtreamError.http(h.statusCode); continue
                }
                return try JSONSerialization.jsonObject(with: data)
            } catch { lastErr = error }
        }
        throw lastErr
    }

    /// Countries that actually have stations, most-stations first.
    static func countries() async throws -> [RadioCountry] {
        JObj.objects(try await get("/json/countries?hidebroken=true")).compactMap { o -> RadioCountry? in
            let code = o.s("iso_3166_1").trimmingCharacters(in: .whitespaces)
            let name = o.s("name").trimmingCharacters(in: .whitespaces)
            let count = o.i("stationcount")
            guard code.count == 2, !name.isBlank, count > 0 else { return nil }
            return RadioCountry(name: name, code: code, count: count)
        }.sorted { $0.count > $1.count }
    }

    /// Top stations in a country (by popularity), de-duplicated, with a working stream URL.
    static func stations(countryCode: String, limit: Int = 500) async throws -> [RadioStation] {
        let path = "/json/stations/bycountrycodeexact/\(countryCode.uppercased())"
            + "?hidebroken=true&order=clickcount&reverse=true&limit=\(limit)"
        var seen = Set<String>()
        var out: [RadioStation] = []
        for o in JObj.objects(try await get(path)) {
            let url = o.s("url_resolved").ifBlank(o.s("url")).trimmingCharacters(in: .whitespaces)
            let name = o.s("name").trimmingCharacters(in: .whitespaces)
            if url.isBlank || name.isBlank { continue }
            if !seen.insert(url).inserted { continue }
            out.append(RadioStation(
                name: name, url: url, favicon: o.s("favicon").trimmingCharacters(in: .whitespaces),
                tags: o.s("tags").trimmingCharacters(in: .whitespaces),
                codec: o.s("codec").trimmingCharacters(in: .whitespaces), bitrate: o.i("bitrate")))
        }
        return out
    }

    /// Station "types" for a country: the tags present, most-common first.
    static func types(_ stations: [RadioStation]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in stations {
            for raw in s.tags.split(separator: ",") {
                let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if !t.isBlank { counts[t, default: 0] += 1 }
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(40).map { (name: $0.key, count: $0.value) }
    }
}
