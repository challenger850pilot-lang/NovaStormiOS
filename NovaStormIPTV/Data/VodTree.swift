import Foundation

/// A movie/series category with its country prefix stripped (the genre part).
struct VodCategoryEntry: Identifiable, Hashable {
    let category: Category
    let label: String
    var id: String { category.id }
}

/// A top-level VOD folder: a country (or brand/theme) grouping several categories.
struct VodCountry: Identifiable, Hashable {
    let name: String
    let flagCode: String?
    let categories: [VodCategoryEntry]
    let emoji: String?
    var id: String { name }
}

private struct Region {
    let name: String
    let flag: String?
}

private struct ParsedVod {
    let country: String
    let flag: String?
    let label: String
}

// Country/language keys (2-letter codes, English + native names, adjectives, common typos)
// → display name + flag ISO code (nil for regions/languages). Keys are accent-stripped and
// uppercased. Brands (NETFLIX, DISNEY+, AMAZON…) are intentionally absent → own folder.
private let countryMap: [String: Region] = {
    var m: [String: Region] = [:]
    func add(_ name: String, _ flag: String?, _ keys: String...) {
        for k in keys { m[k] = Region(name: name, flag: flag) }
    }
    add("English", "gb", "EN", "ENGLISH")
    add("France", "fr", "FR", "FRANCE")
    add("Germany", "de", "DE", "GERMANY", "DEUTSCHLAND")
    add("Spain", "es", "ES", "SPAIN", "ESPANA")
    add("Italy", "it", "IT", "ITALY", "ITALIA")
    add("Greece", "gr", "GR", "GREECE", "GREEK")
    add("Turkey", "tr", "TR", "TURKEY", "TURKISH", "TURKSIH")
    add("Netherlands", "nl", "NL", "NETHERLANDS")
    add("India", "in", "IN", "INDIA", "INDIAN", "HINDI")
    add("Portugal / Brazil", "pt", "PT/BR", "PT", "PORTUGAL")
    add("Brazil", "br", "BR", "BRAZIL")
    add("Philippines", "ph", "PH", "PHILIPPINES")
    add("Québec", "ca", "QC", "QUEBEC")
    add("Israel", "il", "IL", "HEBREW", "ISRAEL")
    add("Iran", "ir", "IR", "PERSIAN", "IRAN")
    add("Poland", "pl", "PL", "POLAND", "POLSKA")
    add("Bulgaria", "bg", "BG", "BULGARIA", "BULGARIYA")
    add("Russia", "ru", "RU", "RUSSIA", "RUSSIAN", "RUSSAIN")
    add("Albania", "al", "AL", "ALBANIA")
    add("Pakistan", "pk", "PK", "PAKISTAN")
    add("Romania", "ro", "RO", "ROMANIA", "ROMANIAN")
    add("Belgium", "be", "BE", "BELGIUM")
    add("China", "cn", "CN", "CHINA")
    add("Malta", "mt", "MT", "MALTA")
    add("Sweden", "se", "SE", "SWEDEN", "SVENSK", "SVENSKA")
    add("Norway", "no", "NO", "NORWAY", "NORSK", "NORGE")
    add("Denmark", "dk", "DK", "DENMARK", "DANSK", "DANSKE")
    add("Finland", "fi", "FI", "FINLAND", "SUOMI", "SUOMEN")
    add("Afghanistan", "af", "AF")
    add("Somalia", "so", "SO")
    add("Arabic", nil, "AR", "ARABIC")
    add("Kurdish", nil, "KU", "KURDISH")
    add("Latin America", nil, "LA", "LATINO", "LATIN")
    add("Nordic", nil, "NORDIC")
    add("Asia", nil, "ASIA")
    add("Ex-Yugoslavia", nil, "EX")
    // Not a country — the provider mislabels its multi-sport bucket as "SOCCER".
    add("Sports", nil, "SOCCER", "SPORT", "SPORTS")
    return m
}()

private func emojiFor(_ name: String) -> String? { name == "Sports" ? "🏆" : nil }

// English-language streaming services fold into the "English" folder; an explicitly
// regional sub-category (e.g. "Netflix Asia") still routes to that region.
private let brands: Set<String> = [
    "NETFLIX", "DISNEY+", "DISNEY", "AMAZON", "APPLE+", "APPLE", "HBO", "HBOMAX", "MAX",
    "PARAMOUNT+", "PARAMOUNT", "PEACOCK", "SHOWTIME", "SKY", "VIAPLAY", "DISCOVERY+",
    "DISCOVERY", "JOYN", "VIDEOLAND", "UNIVERSAL", "DREAMWORKS", "NICKELODEON", "HULU",
    "STARZ", "BRITBOX", "ATRESPLAYER", "CRUNCHYROLL",
]

private func hasArabic(_ s: String) -> Bool {
    s.unicodeScalars.contains { $0.value >= 0x0600 && $0.value <= 0x06FF }
}

/// Accent-strip + uppercase for map lookup ("España" → "ESPANA").
private func normKey(_ s: String) -> String {
    s.folding(options: .diacriticInsensitive, locale: nil).uppercased()
}

/// A country/region NAME (not a 2-letter code) mentioned inside a brand's sub-label.
private func regionInLabel(_ label: String) -> Region? {
    for w in label.components(separatedBy: CharacterSet(charactersIn: " /\t")) where w.count >= 3 {
        if let hit = countryMap[normKey(w)] { return hit }
    }
    return nil
}

private func parseVod(_ catName: String) -> ParsedVod {
    let t = catName.trimmingCharacters(in: .whitespaces)
    if hasArabic(t) { return ParsedVod(country: "Arabic", flag: nil, label: t) }
    let head: String
    let label: String
    if let r = t.range(of: " - ") {
        head = String(t[t.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        label = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces).ifBlank(t)
    } else {
        let parts = t.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        head = parts.first ?? t
        label = parts.count > 1 ? parts[1] : t
    }
    let hk = normKey(head)
    // 1. Head is a country/language → that folder. English keeps the full name as the
    //    sub-label so services/types stay distinguishable inside the English folder.
    if let hit = countryMap[hk] {
        return ParsedVod(country: hit.name, flag: hit.flag, label: hit.name == "English" ? t : label)
    }
    // 2. Head is a streaming brand → regional content routes to that region, else English.
    if brands.contains(hk) {
        if let hit = regionInLabel(label) { return ParsedVod(country: hit.name, flag: hit.flag, label: t) }
        return ParsedVod(country: "English", flag: "gb", label: t)
    }
    // 3. Anything else becomes its own folder.
    return ParsedVod(country: head, flag: nil, label: label)
}

extension Array where Element == Category {
    /// Group categories into Country (or brand) folders, biggest first.
    func groupByCountry() -> [VodCountry] {
        var order: [String] = []
        var entries: [String: [VodCategoryEntry]] = [:]
        var meta: [String: Region] = [:]
        for c in self {
            let p = parseVod(c.name)
            let key = p.country.lowercased()
            if entries[key] == nil {
                order.append(key)
                meta[key] = Region(name: p.country, flag: p.flag)
            }
            entries[key, default: []].append(VodCategoryEntry(category: c, label: p.label))
        }
        return order.map { key -> VodCountry in
            let region = meta[key] ?? Region(name: key, flag: nil)
            return VodCountry(name: region.name, flagCode: region.flag,
                              categories: entries[key] ?? [], emoji: emojiFor(region.name))
        }.sorted { a, b in
            if a.categories.count != b.categories.count { return a.categories.count > b.categories.count }
            return a.name.lowercased() < b.name.lowercased()
        }
    }
}

private let vodCodeStrip = try! NSRegularExpression(pattern: "^[A-Za-z/]{2,6}\\s*-\\s*")
private let vodCodeRx = try! NSRegularExpression(pattern: "^\\s*(?:4[Kk]-)?([A-Za-z]{2,5})\\b")
private let enPlatforms: Set<String> = [
    "NF", "AMZ", "PRMT", "PMT", "PARA", "UNV", "DSNY", "DIS", "HBO", "MAX",
    "ATV", "APTV", "PCOK", "HULU", "SHO", "STARZ",
]

/// Strip a leading "XX - " country/language code from a title for display.
func stripVodCode(_ title: String) -> String {
    let ns = title as NSString
    let out = vodCodeStrip.stringByReplacingMatches(
        in: title, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        .trimmingCharacters(in: .whitespaces)
    return out.ifBlank(title)
}

/// Short language code from a name prefix (EN, DE, IT…) for the poster badge.
func vodLangCode(_ name: String) -> String {
    let ns = name as NSString
    guard let m = vodCodeRx.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)),
          m.numberOfRanges > 1 else { return "" }
    let c = ns.substring(with: m.range(at: 1)).uppercased()
    if c == "EN" || enPlatforms.contains(c) { return "EN" }
    return (2...3).contains(c.count) ? c : ""
}

/// Flag emoji for an ISO country code ("gb" → 🇬🇧).
func flagEmoji(_ code: String?) -> String {
    guard let code = code, code.count == 2 else { return "" }
    var s = ""
    for u in code.uppercased().unicodeScalars {
        if let v = UnicodeScalar(127397 + u.value) { s.unicodeScalars.append(v) }
    }
    return s
}
