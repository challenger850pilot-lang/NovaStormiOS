import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on non-Apple platforms (local type-checks)
#endif

/// Baked-in login for private builds so a fresh install connects with no typing.
/// Leave `baseUrl` empty for a public build to get a login screen instead.
enum Defaults {
    static let baseUrl = "http://192.168.1.88:8091"      // home LAN
    static let tunnelUrl = "http://10.77.0.1:8091"       // over the WireGuard app when away
    static let username = "rv"
    static let password = "tv"
    static var enabled: Bool { !baseUrl.isEmpty }
    static func auth() -> XtreamAuth { XtreamAuth(baseUrl: baseUrl, username: username, password: password) }
}

/// Persisted login.
enum Prefs {
    private static let key = "novastorm_auth"

    static func auth() -> XtreamAuth? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let a = try? JSONDecoder().decode(XtreamAuth.self, from: data),
              !a.baseUrl.isBlank, !a.username.isBlank else { return nil }
        return a
    }

    static func save(_ a: XtreamAuth) {
        if let data = try? JSONEncoder().encode(a) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Picks the URL the gateway is actually reachable on: LAN at home, tunnel when away.
enum GatewayResolver {
    static func reachable(_ base: String, timeout: TimeInterval = 2.5) async -> Bool {
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let u = URL(string: root + "/health") else { return false }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let h = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(h.statusCode)
    }

    static func resolve(lan: String) async -> String {
        if await reachable(lan) { return lan }
        if await reachable(Defaults.tunnelUrl) { return Defaults.tunnelUrl }
        return lan
    }
}
