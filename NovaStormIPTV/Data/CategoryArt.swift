import Foundation

/// Artwork for sub-category rows: a real brand logo when the name is recognized (Google's
/// favicon service, a reliable PNG), otherwise a generic emoji chosen by keyword.
enum CategoryArt {
    private static let brands: [(String, String)] = [
        ("netflix", "netflix.com"),
        ("prime video", "primevideo.com"), ("amazon prime", "primevideo.com"),
        ("amazon", "primevideo.com"), ("prime", "primevideo.com"),
        ("disney", "disneyplus.com"),
        ("hbo max", "max.com"), ("hbomax", "max.com"), ("hbo", "hbo.com"), ("max", "max.com"),
        ("paramount", "paramountplus.com"), ("peacock", "peacocktv.com"),
        ("apple tv", "apple.com"), ("appletv", "apple.com"), ("apple", "apple.com"),
        ("viaplay", "viaplay.com"), ("joyn", "joyn.de"), ("videoland", "videoland.nl"),
        ("hulu", "hulu.com"), ("espn", "espn.com"),
        ("nickelodeon", "nick.com"), ("nick jr", "nick.com"), ("nick", "nick.com"),
        ("discovery", "discovery.com"), ("sky", "sky.com"),
        ("cnn", "cnn.com"), ("fox news", "foxnews.com"), ("fox", "fox.com"),
        ("cbs", "cbs.com"), ("nbc", "nbc.com"), ("abc", "abc.com"), ("bbc", "bbc.co.uk"),
        ("mtv", "mtv.com"), ("showtime", "sho.com"), ("starz", "starz.com"), ("amc", "amc.com"),
        ("crunchyroll", "crunchyroll.com"), ("youtube", "youtube.com"),
        ("tubi", "tubitv.com"), ("pluto", "pluto.tv"),
    ]

    static func logoUrl(_ name: String) -> String? {
        let n = name.lowercased()
        for (kw, dom) in brands where n.contains(kw) {
            return "https://www.google.com/s2/favicons?domain=\(dom)&sz=128"
        }
        return nil
    }

    static func emoji(_ name: String, default def: String = "🎬") -> String {
        let n = name.lowercased()
        func any(_ ks: [String]) -> Bool { ks.contains { n.contains($0) } }
        if n.contains("news") { return "📰" }
        if any(["sport", "espn", "football", "soccer", "nba", "nfl", "ufc", "boxing", "fight"]) { return "🏆" }
        if any(["kids", "cartoon", "nick", "junior", "family", "disney"]) { return "🧸" }
        if n.contains("horror") { return "👻" }
        if n.contains("comedy") { return "😂" }
        if n.contains("drama") { return "🎭" }
        if any(["documentary", "docu", "history", "science", "nature", "geographic"]) { return "🎞️" }
        if n.contains("4k") || n.contains("uhd") { return "💎" }
        if any(["music", "pop", "rock", "jazz", "reggae", "latin", "hip hop", "rap",
                "dance", "electronic", "classical", "country", "80s", "90s", "70s", "oldies"]) { return "🎵" }
        if any(["movie", "cinema", "film"]) { return "🎬" }
        return def
    }
}
