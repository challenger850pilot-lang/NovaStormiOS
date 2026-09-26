import SwiftUI

/// Radio: country → station type → stations → play. Powered by Radio Browser.
struct RadioView: View {
    @State private var countries: [RadioCountry] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let e = error {
                    ErrorRetry(message: e) { Task { await load() } }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(countries) { c in
                        NavigationLink { RadioCountryView(country: c) } label: {
                            HStack {
                                Text(flagEmoji(c.code))
                                Text(c.name)
                                Spacer()
                                Text("\(c.count)").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Radio")
            .screenBackground()
        }
        .task { if countries.isEmpty { await load() } }
    }

    private func load() async {
        error = nil; loading = true
        do { countries = try await RadioBrowser.countries() }
        catch { self.error = "Couldn't reach Radio Browser: \(error.localizedDescription)" }
        loading = false
    }
}

/// Station types for one country (All + genres from tags).
struct RadioCountryView: View {
    let country: RadioCountry
    @State private var stations: [RadioStation] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let types = RadioBrowser.types(stations)
                List {
                    NavigationLink {
                        RadioStationsView(title: "All stations", stations: stations)
                    } label: {
                        HStack {
                            Image(systemName: "radio").foregroundStyle(Theme.accent)
                            Text("All stations")
                            Spacer()
                            Text("\(stations.count) stations").foregroundStyle(Theme.muted)
                        }
                    }
                    ForEach(types, id: \.name) { t in
                        NavigationLink {
                            RadioStationsView(title: t.name.capitalized, stations: stations.filter { st in
                                st.tags.split(separator: ",").contains {
                                    $0.trimmingCharacters(in: .whitespaces).lowercased() == t.name
                                }
                            })
                        } label: {
                            HStack {
                                Image(systemName: "music.note").foregroundStyle(Theme.accent)
                                Text(t.name.capitalized)
                                Spacer()
                                Text("\(t.count) stations").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { if stations.isEmpty { await load() } }
    }

    private func load() async {
        error = nil; loading = true
        do { stations = try await RadioBrowser.stations(countryCode: country.code) }
        catch { self.error = "Couldn't load stations for \(country.name)." }
        loading = false
    }
}

struct RadioStationsView: View {
    let title: String
    let stations: [RadioStation]

    var body: some View {
        Group {
            if stations.isEmpty {
                Text("No stations here.").foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(stations) { s in
                    NavigationLink {
                        PlayerView(title: s.name, url: s.url, resume: nil, artwork: s.favicon)
                    } label: {
                        HStack(spacing: 12) {
                            RadioLogo(url: s.favicon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).lineLimit(1)
                                if !s.subtitle.isBlank {
                                    Text(s.subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
    }
}

struct RadioLogo: View {
    let url: String
    var body: some View {
        Color.black.opacity(0.25)
            .frame(width: 44, height: 44)
            .overlay {
                if let u = URL(string: url), !url.isBlank {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFit().padding(3) }
                        else { Image(systemName: "radio").foregroundStyle(Theme.muted) }
                    }
                } else {
                    Image(systemName: "radio").foregroundStyle(Theme.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
