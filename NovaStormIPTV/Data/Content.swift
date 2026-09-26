import Foundation

/// Pay-per-view categories/sections.
func isPpvLabel(_ s: String) -> Bool { s.range(of: "ppv", options: .caseInsensitive) != nil }

/// Adult / X-rated categories or sections. "Adult Swim", adult animation and the jiu-jitsu
/// "Adult Black Belt" event are explicitly NOT adult content.
func isAdultLabel(_ s: String) -> Bool {
    let n = s.lowercased()
    for kw in ["erotic", "xxx", "porn", "hentai", "18+", "brazzers", "playboy", "onlyfans"] {
        if n.contains(kw) { return true }
    }
    if n.contains("adult") {
        for excl in ["swim", "animation", "cartoon", "black belt"] where n.contains(excl) { return false }
        return true
    }
    return false
}
