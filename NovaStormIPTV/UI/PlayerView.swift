import SwiftUI
import AVKit

/// AVPlayer screen. Live channels stream HLS from the gateway; movies/episodes are MP4 or the
/// gateway's HLS remux. Movies/episodes remember where you left off.
struct PlayerView: View {
    let title: String
    let url: String
    let resume: WatchItem?          // nil for live
    var artwork: String? = nil      // radio: station logo shown over the (audio-only) player

    @StateObject private var model = PlayerModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let p = model.player {
                VideoPlayer(player: p).ignoresSafeArea()
            }
            // Radio is audio-only: show the station logo + name instead of a black screen.
            if let art = artwork {
                VStack(spacing: 18) {
                    Color.white.opacity(0.06)
                        .frame(width: 220, height: 220)
                        .overlay {
                            if let u = URL(string: art), !art.isBlank {
                                AsyncImage(url: u) { phase in
                                    if let img = phase.image { img.resizable().scaledToFit().padding(10) }
                                    else { Image(systemName: "radio").font(.system(size: 80)).foregroundStyle(Theme.muted) }
                                }
                            } else {
                                Image(systemName: "radio").font(.system(size: 80)).foregroundStyle(Theme.muted)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(title).foregroundStyle(.white).font(.title3.bold()).multilineTextAlignment(.center)
                    Label("Live radio", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent)
                }
                .padding()
                .allowsHitTesting(false)
            }
            if let f = model.failure {
                Text(f).foregroundStyle(.white).padding().multilineTextAlignment(.center)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if model.audioOptions.count > 1 {
                    Menu {
                        ForEach(model.audioOptions.indices, id: \.self) { i in
                            Button {
                                model.selectAudio(index: i)
                            } label: {
                                if model.selectedAudio == i {
                                    Label(model.audioOptions[i].displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.audioOptions[i].displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "waveform")
                    }
                }
            }
        }
        .onAppear { model.start(url: url, resume: resume) }
        .onDisappear { model.stop() }
    }
}

/// Owns the AVPlayer and the progress bookkeeping so SwiftUI re-renders don't disturb playback.
@MainActor
final class PlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var failure: String?
    @Published var audioOptions: [AVMediaSelectionOption] = []
    @Published var selectedAudio: Int?
    private var audioGroup: AVMediaSelectionGroup?
    private var resume: WatchItem?
    private var timeObserver: Any?

    func start(url: String, resume: WatchItem?) {
        guard player == nil else { return }
        guard let u = URL(string: url) else {
            failure = "Bad stream URL."
            return
        }
        self.resume = resume
        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        loadAudioOptions(for: item)
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

    private func loadAudioOptions(for item: AVPlayerItem) {
        Task { @MainActor in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            audioGroup = group
            audioOptions = group.options
            if let current = item.currentMediaSelection.selectedMediaOption(in: group) {
                selectedAudio = group.options.firstIndex(where: { $0 === current })
            } else {
                selectedAudio = group.options.isEmpty ? nil : 0
            }
        }
    }

    func selectAudio(index: Int) {
        guard let item = player?.currentItem, let group = audioGroup,
              audioOptions.indices.contains(index) else { return }
        item.select(audioOptions[index], in: group)
        selectedAudio = index
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
