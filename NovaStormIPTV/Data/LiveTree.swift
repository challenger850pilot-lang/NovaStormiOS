import Foundation

/// A sub-folder within a live category, named by a "#### … ####" divider row.
struct LiveSection: Identifiable {
    let label: String
    let channels: [LiveChannel]
    var id: String { label }
}

extension LiveChannel {
    /// Playlist divider rows like "#### PRIME ####" mark sections; they aren't real channels.
    var isSeparator: Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.count >= 2 && t.hasPrefix("#") && t.hasSuffix("#")
    }

    fileprivate var sectionLabel: String {
        name.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
    }
}

extension Array where Element == LiveChannel {
    /// Split on divider rows. Channels before the first divider land under "Channels".
    func splitSections() -> [LiveSection] {
        var out: [LiveSection] = []
        var label = ""
        var current: [LiveChannel] = []
        for ch in self {
            if ch.isSeparator {
                if !current.isEmpty { out.append(LiveSection(label: label.ifBlank("Channels"), channels: current)) }
                label = ch.sectionLabel
                current = []
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(LiveSection(label: label.ifBlank("Channels"), channels: current)) }
        return out
    }
}
