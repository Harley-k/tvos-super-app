import AVKit
import Combine
import SwiftUI

@MainActor
final class PlaybackSession: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var message: String?
    @Published private(set) var playbackSeconds = 0.0
    @Published private(set) var buffering = true
    private var watchdog: Task<Void, Never>?
    private var lastSaved = 0.0
    private var isLive = false
    private var subscriptions = Set<AnyCancellable>()
    private var timeObserver: Any?
    private var runID: UUID?
    private var key: EpisodeKey?
    private var store: ResumeStore?
    private var canSave = false
    private var ended = false

    func start(url: URL, key: EpisodeKey, resumeAt: Double?, store: ResumeStore, isLive: Bool) {
        stop()
        let run = UUID()
        runID = run
        self.key = key
        self.store = store
        message = nil
        ended = false
        buffering = true
        playbackSeconds = 0
        lastSaved = 0
        self.isLive = isLive
        armTimeout(run: run)
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

        player.publisher(for: \.timeControlStatus, options: [.new])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.runID == run, self.message == nil, !self.ended else { return }
                if status == .waitingToPlayAtSpecifiedRate {
                    self.buffering = true
                    self.armTimeout(run: run)
                } else if status == .playing {
                    self.buffering = false
                    self.watchdog?.cancel()
                } else if self.canSave {
                    self.buffering = false
                    self.watchdog?.cancel()
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
                self.watchdog?.cancel()
                if !isLive { store.finish(key) }
            }.store(in: &subscriptions)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.runID == run else { return }
                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }
                self.playbackSeconds = seconds
                if abs(seconds - self.lastSaved) >= 5 {
                    self.lastSaved = seconds
                    self.save(seconds)
                }
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
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
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

    private func armTimeout(run: UUID) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.runID == run, self.buffering, self.message == nil else { return }
            self.fail("等待片源超过 15 秒。请重试或返回选择其他片源。")
        }
    }

    func checkpoint() { save(player.currentTime().seconds) }

    private func fail(_ reason: String = "无法播放这个片源。请检查链接、网络和播放权限后重试。") {
        save(player.currentTime().seconds)
        canSave = false
        player.pause()
        watchdog?.cancel()
        buffering = false
        message = reason
    }

    private func save(_ seconds: Double) {
        guard canSave, !ended, !isLive, let key, let store else { return }
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
        watchdog?.cancel()
        watchdog = nil
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
    let isLive: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = PlaybackSession()
    @Namespace private var playerFocus

    var body: some View {
        VStack(spacing: 16) {
            if let message = session.message {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(episode.title).font(.headline)
                Text(message).foregroundStyle(.yellow).accessibilityIdentifier("playback-error")
                Button("重试") {
                    start(at: session.playbackSeconds >= 2 ? session.playbackSeconds : resumeAt)
                }
                Spacer()
            } else {
                ZStack {
                    NativePlayer(player: session.player)
                        .accessibilityLabel(episode.title)
                    if session.buffering {
                        ProgressView("正在打开片源…")
                            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 26) {
                Button(isLive ? "返回频道" : "返回分集") { close() }
                    .accessibilityIdentifier("playback-exit")
                    .trialDefaultFocus(true, in: playerFocus)
                    .trialCloseShortcut()
                Label(episode.title, systemImage: isLive ? "dot.radiowaves.left.and.right" : "film").lineLimit(1)
                Spacer()
                if isLive {
                    Text("直播").foregroundStyle(.orange)
                } else {
                    Text(timestamp).monospacedDigit()
                        .accessibilityIdentifier("playback-progress")
                        .accessibilityValue(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"),
                                                   session.playbackSeconds))
                }
            }.padding(.horizontal, 44).padding(.bottom, 20)
        }
        .trialFocusScope(playerFocus)
        .background(Color.black)
        .onAppear { start(at: resumeAt) }
        .onDisappear(perform: session.stop)
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.checkpoint() } }
        .trialExitCommand(perform: close)
    }

    private var timestamp: String {
        let time = Int(min(session.playbackSeconds, 999_999))
        return String(format: "%d:%02d", time / 60, time % 60)
    }

    private func close() {
        session.stop()
        dismiss()
    }

    private func start(at position: Double?) {
        session.start(url: episode.streamURL, key: episodeKey, resumeAt: position, store: store, isLive: isLive)
    }
}

#if os(macOS)
private struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#elseif os(tvOS)
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

#endif
