import SwiftUI
import AVKit

/// AVPlayer screen. Live channels stream HLS from the gateway; movies/episodes are MP4 or the
/// gateway's HLS remux. Movies/episodes remember where you left off.
struct PlayerView: View {
    let title: String
    let url: String
    let resume: WatchItem?          // nil for live

    @StateObject private var model = PlayerModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let p = model.player {
                VideoPlayer(player: p).ignoresSafeArea()
            }
            if let f = model.failure {
                Text(f).foregroundStyle(.white).padding().multilineTextAlignment(.center)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { model.start(url: url, resume: resume) }
        .onDisappear { model.stop() }
    }
}

/// Owns the AVPlayer and the progress bookkeeping so SwiftUI re-renders don't disturb playback.
@MainActor
final class PlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var failure: String?
    private var resume: WatchItem?
    private var timeObserver: Any?

    func start(url: String, resume: WatchItem?) {
        guard player == nil else { return }
        guard let u = URL(string: url) else {
            failure = "Bad stream URL."
            return
        }
        self.resume = resume
        let p = AVPlayer(playerItem: AVPlayerItem(url: u))
        p.automaticallyWaitsToMinimizeStalling = true
        if let r = resume {
            let pos = History.position(kind: r.kind, id: r.id)
            if pos > 15_000 { p.seek(to: CMTime(value: pos, timescale: 1000)) }
            // Save progress every 5 s so Continue Watching is right even if the app is killed.
            // AVFoundation calls this from a non-isolated context; hop back onto the main actor.
            timeObserver = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
                Task { @MainActor in self?.save() }
            }
        }
        player = p
        p.play()
    }

    func stop() {
        guard let p = player else { return }
        save()
        if let o = timeObserver { p.removeTimeObserver(o) }
        timeObserver = nil
        p.pause()
        player = nil
    }

    private func save() {
        guard var r = resume, let p = player, let item = p.currentItem else { return }
        let dur = item.duration
        guard dur.isNumeric, dur.seconds.isFinite, dur.seconds > 0 else { return }
        r.positionMs = Int64(p.currentTime().seconds * 1000)
        r.durationMs = Int64(dur.seconds * 1000)
        r.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        History.record(r)
    }
}
