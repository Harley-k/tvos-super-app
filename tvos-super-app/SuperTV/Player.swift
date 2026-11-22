import AVKit
import Combine
import SwiftUI

@MainActor
final class PlaybackSession: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var message: String?
    private var subscriptions = Set<AnyCancellable>()
    private var timeObserver: Any?
    private var runID: UUID?
    private var key: EpisodeKey?
    private var store: ResumeStore?
    private var canSave = false
    private var ended = false

    func start(url: URL, key: EpisodeKey, resumeAt: Double?, store: ResumeStore) {
        stop()
        let run = UUID()
        runID = run
        self.key = key
        self.store = store
        message = nil
        ended = false
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        item.publisher(for: \.status, options: [.initial, .new])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item, self.runID == run else { return }
                switch status {
                case .readyToPlay:
                    self.beginReadyPlayback(item: item, run: run, resumeAt: resumeAt)
                case .failed:
                    self.fail()
                default: break
                }
            }.store(in: &subscriptions)

        let center = NotificationCenter.default
        center.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.runID == run else { return }
                self.fail()
            }.store(in: &subscriptions)
        center.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.runID == run else { return }
                self.ended = true
                store.finish(key)
            }.store(in: &subscriptions)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.runID == run else { return }
                self.save(time.seconds)
            }
        }
    }

    private func beginReadyPlayback(item: AVPlayerItem, run: UUID, resumeAt: Double?) {
        guard let position = resumeAt, position >= 2, position.isFinite else {
            canSave = true
            player.play()
            return
        }
        let duration = item.duration.seconds
        if duration.isFinite && position >= duration - 1 {
            if let store, let key { store.finish(key) }
            canSave = true
            player.play()
            return
        }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self] completed in
            Task { @MainActor in
                guard let self, self.runID == run, self.message == nil else { return }
                if completed {
                    self.canSave = true
                    self.player.play()
                } else if self.player.currentItem?.status == .readyToPlay {
                    self.canSave = true
                    self.player.play()
                }
            }
        }
    }

    private func fail() {
        save(player.currentTime().seconds)
        canSave = false
        player.pause()
        message = "无法播放这段视频。请检查网络后重试。"
    }

    private func save(_ seconds: Double) {
        guard canSave, !ended, let key, let store else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        if seconds.isFinite, duration.isFinite, duration > 0, seconds >= duration - 1 {
            store.finish(key)
        } else {
            store.record(seconds, for: key)
        }
    }

    func stop() {
        save(player.currentTime().seconds)
        runID = nil
        canSave = false
        subscriptions.removeAll()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        key = nil
        store = nil
    }
}

@MainActor
struct PlaybackScreen: View {
    let episode: Episode
    let episodeKey: EpisodeKey
    let resumeAt: Double?
    let store: ResumeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = PlaybackSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message = session.message {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(episode.title).font(.headline)
                    Text(message).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        Button("重试") { start(at: resumeAt) }
                        Button("返回分集") { dismiss() }
                    }
                }
            } else {
                NativePlayer(player: session.player)
                    .ignoresSafeArea()
                    .accessibilityLabel(episode.title)
            }
        }
        .onAppear { start(at: resumeAt) }
        .onDisappear(perform: session.stop)
    }

    private func start(at position: Double?) {
        session.start(url: episode.streamURL, key: episodeKey, resumeAt: position, store: store)
    }
}

private struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
