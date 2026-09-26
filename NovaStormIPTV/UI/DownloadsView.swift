import SwiftUI

/// The Download / progress / Downloaded button shown next to Play on a movie. Reflects the
/// live state of the download for `id` and lets the user start, cancel or delete it.
struct DownloadControl: View {
    let id: String
    let title: String
    let poster: String
    let container: String
    let url: String
    @ObservedObject private var downloads = Downloads.shared
    @State private var confirmDelete = false

    var body: some View {
        let item = downloads.items[id]
        Group {
            switch item?.status {
            case .some(.done):
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .frame(width: 52, height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .confirmationDialog("Delete this download?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete download", role: .destructive) { downloads.delete(id) }
                    Button("Cancel", role: .cancel) {}
                }
            case .some(.downloading):
                Button(role: .destructive) { downloads.delete(id) } label: {
                    ZStack {
                        CircularProgress(fraction: Double(item?.percent ?? 0) / 100)
                        Text("\(item?.percent ?? 0)%").font(.system(size: 11, weight: .bold))
                    }
                    .frame(width: 52, height: 48)
                }
                .buttonStyle(.bordered)
            case .some(.failed):
                Button { start() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2).frame(width: 52, height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            default:
                Button { start() } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2).frame(width: 52, height: 48)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func start() {
        downloads.start(id: id, title: title, poster: poster, container: container, url: url)
    }
}

/// A thin ring that fills clockwise with `fraction` (0…1).
struct CircularProgress: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
    }
}

/// The list of downloaded (and in-flight) movies. Plays the local file so it works offline.
struct DownloadsView: View {
    @ObservedObject private var downloads = Downloads.shared

    private var sorted: [DownloadItem] {
        downloads.items.values.sorted {
            if $0.status != $1.status {
                // Downloading first, then done, then failed.
                return rank($0.status) < rank($1.status)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func rank(_ s: DownloadStatus) -> Int {
        switch s { case .downloading: return 0; case .done: return 1; case .failed: return 2 }
    }

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(Theme.muted)
                    Text("No downloads yet").font(.headline)
                    Text("Tap the download button on any movie to save it here for offline play.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List {
                    ForEach(sorted) { item in
                        DownloadRow(item: item)
                    }
                    .onDelete { idx in
                        idx.map { sorted[$0].id }.forEach { downloads.delete($0) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    @ObservedObject private var downloads = Downloads.shared

    private var resume: WatchItem {
        WatchItem(kind: "movie", id: item.id, title: item.title, poster: item.poster,
                  container: item.container,
                  url: downloads.localURL(item.id)?.absoluteString ?? item.url,
                  positionMs: 0, durationMs: 0, updatedAt: 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Color.black.opacity(0.25)
                .frame(width: 46, height: 66)
                .overlay {
                    if let u = URL(string: item.poster), !item.poster.isBlank {
                        AsyncImage(url: u) { p in
                            if let img = p.image { img.resizable().scaledToFill() } else { Color.clear }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).lineLimit(2)
                switch item.status {
                case .done:
                    Label(sizeText, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                case .downloading:
                    ProgressView(value: Double(item.percent), total: 100).tint(Theme.accent)
                    Text("\(item.percent)%  ·  \(sizeText)").font(.caption).foregroundStyle(Theme.muted)
                case .failed:
                    Text(item.message.isBlank ? "Failed — tap retry" : item.message)
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer()

            if item.status == .done {
                NavigationLink {
                    PlayerView(title: item.title, url: resume.url, resume: resume)
                } label: {
                    Image(systemName: "play.circle.fill").font(.title).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            } else if item.status == .failed {
                Button {
                    downloads.start(id: item.id, title: item.title, poster: item.poster,
                                    container: item.container, url: item.url)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill").font(.title).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var sizeText: String {
        let bytes = item.status == .done ? item.total : item.bytes
        if bytes <= 0 { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
