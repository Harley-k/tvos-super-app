import AVFoundation
import Foundation
import CoreVideo
import QuartzCore
import Darwin

private enum ProbeError: LocalizedError {
    case invalidArguments, missingMedia, wrongTracks, readiness, noFrames, progress, resume, episodeIsolation
    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "Expected two embedded MP4 paths"
        case .missingMedia: return "Embedded sample file not found"
        case .wrongTracks: return "Expected both audio and video tracks"
        case .readiness: return "AVPlayer item did not become ready to play"
        case .noFrames: return "No real video frame decoded"
        case .progress: return "AVPlayer currentTime did not advance"
        case .resume: return "Reopened first episode did not resume at its stored position"
        case .episodeIsolation: return "Second episode inherited another episode's position"
        }
    }
}

@main
private struct MacPlaybackProbe {
    @MainActor
    static func main() async {
        do {
            try await run()
            print("PASS: macOS AVFoundation decoded frames, took real time measurements, sought to the stored position and opened a different episode near zero.")
        } catch {
            print("FAIL macOS media probe: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard args.count == 2 else { throw ProbeError.invalidArguments }
        let paths = args.map { URL(fileURLWithPath: $0) }
        guard paths.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw ProbeError.missingMedia
        }
        let suite = "SuperTV.MacCI.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let aKey = EpisodeKey(showID: "mac-authored-sample", episodeID: "one")
        let bKey = EpisodeKey(showID: "mac-authored-sample", episodeID: "two")
        let store = ResumeStore(defaults: defaults)
        let initial = try await measure(paths[0], startAt: nil, seconds: 5.5, deadline: 13)
        guard initial >= 5.5 else { throw ProbeError.progress }
        store.record(initial, for: aKey)
        let reopened = ResumeStore(defaults: defaults)
        guard let saved = reopened.position(for: aKey), abs(saved - initial) < 0.01,
              reopened.position(for: bKey) == nil else { throw ProbeError.resume }
        let resumed = try await measure(paths[0], startAt: saved, seconds: saved - 0.6,
                                        ceiling: saved + 3, deadline: 5)
        guard resumed >= saved - 0.6 else { throw ProbeError.resume }
        let other = try await measure(paths[1], startAt: reopened.position(for: bKey),
                                       seconds: 0.2, ceiling: 2, deadline: 5)
        guard other < 2 && other < saved - 2 else { throw ProbeError.episodeIsolation }
        print(String(format: "AVPlayer times: first %.2fs, resumed %.2fs, other %.2fs", initial, resumed, other))
    }

    @MainActor
    private static func measure(_ url: URL, startAt: Double?, seconds: Double,
                                ceiling: Double = .infinity, deadline: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard !video.isEmpty, !audio.isEmpty else { throw ProbeError.wrongTracks }

        let item = AVPlayerItem(asset: asset)
        let pixels = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(pixels)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        defer {
            player.pause()
            item.remove(pixels)
            player.replaceCurrentItem(with: nil)
        }
        let readyBy = CACurrentMediaTime() + 8
        while item.status == .unknown, CACurrentMediaTime() < readyBy {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard item.status == .readyToPlay else { throw ProbeError.readiness }
        if let saved = startAt {
            let finished = await player.seek(to: CMTime(seconds: saved, preferredTimescale: 600),
                                              toleranceBefore: .zero, toleranceAfter: .zero)
            guard finished else { throw ProbeError.resume }
        }
        player.play()
        var decoded = false
        let started = CACurrentMediaTime()
        while CACurrentMediaTime() - started < deadline {
            let t = pixels.itemTime(forHostTime: CACurrentMediaTime())
            if t.isValid, pixels.hasNewPixelBuffer(forItemTime: t),
               let image = pixels.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil),
               CVPixelBufferGetWidth(image) == 640, CVPixelBufferGetHeight(image) == 360 {
                decoded = true
            }
            let current = player.currentTime().seconds
            if decoded && current.isFinite && current >= seconds, current < ceiling, player.rate > 0 {
                return current
            }
            if item.status == .failed { throw ProbeError.progress }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw decoded ? ProbeError.progress : ProbeError.noFrames
    }
}
