import Foundation
import SwiftUI

/// App-wide connection state: resolves the gateway URL, authenticates, holds the catalog.
@MainActor
final class Session: ObservableObject {
    enum State {
        case connecting
        case ready(Catalog)
        case failed(String)
    }

    @Published var state: State = .connecting
    @Published private(set) var gatewayBase = ""

    var catalog: Catalog? {
        if case .ready(let c) = state { return c }
        return nil
    }

    func connect() async {
        state = .connecting
        let saved = Prefs.auth() ?? (Defaults.enabled ? Defaults.auth() : nil)
        guard let auth = saved else {
            state = .failed("No gateway configured.")
            return
        }
        let base = await GatewayResolver.resolve(lan: auth.baseUrl)
        gatewayBase = base
        let client = XtreamClient(auth: XtreamAuth(baseUrl: base, username: auth.username, password: auth.password))
        guard await client.authenticate() else {
            state = .failed("Couldn't reach the gateway at \(base).\nAt home: join the home Wi-Fi. Away: turn on the WireGuard tunnel first.")
            return
        }
        Prefs.save(auth)
        state = .ready(Catalog(client: client))
    }
}
