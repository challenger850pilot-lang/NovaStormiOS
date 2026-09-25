import SwiftUI

/// A 2:3 poster tile with a title beneath and an optional language badge.
struct PosterCard: View {
    let title: String
    let poster: String
    var badge: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.25)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if let u = URL(string: poster), !poster.isBlank {
                            AsyncImage(url: u) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.badge.opacity(0.9))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                        .padding(4)
                }
            }
            Text(title).font(.caption).lineLimit(1).foregroundStyle(Theme.muted)
        }
    }
}

/// Adaptive poster grid used by Movies, Series and Search.
struct PosterGrid<Item: Identifiable & Hashable, Destination: View>: View {
    let items: [Item]
    let title: (Item) -> String
    let poster: (Item) -> String
    var badge: (Item) -> String = { _ in "" }
    @ViewBuilder let destination: (Item) -> Destination

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                NavigationLink {
                    destination(item)
                } label: {
                    PosterCard(title: title(item), poster: poster(item), badge: badge(item))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

struct ChannelRow: View {
    let channel: LiveChannel

    var body: some View {
        HStack(spacing: 12) {
            Color.black.opacity(0.25)
                .frame(width: 64, height: 40)
                .overlay {
                    if let u = URL(string: channel.icon), !channel.icon.isBlank {
                        AsyncImage(url: u) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit().padding(3)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(channel.name).lineLimit(1)
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(Theme.accent)
        }
    }
}

struct ErrorRetry: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

/// A country/brand folder row with its flag (or emoji) and category count.
struct CountryRow: View {
    let country: VodCountry

    var body: some View {
        HStack {
            Text(country.emoji ?? flagEmoji(country.flagCode))
            Text(country.name)
            Spacer()
            Text("\(country.categories.count)").foregroundStyle(Theme.muted)
        }
    }
}
