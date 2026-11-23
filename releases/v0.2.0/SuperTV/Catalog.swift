import Foundation

struct DramaCatalog {
    let shows: [Drama]
    init(shows: [Drama]) { self.shows = shows }
    private struct Feed: Decodable { let shows: [Drama] }

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode(Feed.self, from: data).shows
        var seen = Set<String>()
        guard !decoded.isEmpty, decoded.count <= 200, decoded.allSatisfy({ show in
            !show.id.isEmpty && show.id.count <= 100 && seen.insert(show.id).inserted
                && !show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !show.episodes.isEmpty && show.episodes.count <= 400 && show.hasValidEpisodeIDs
        }) else { throw CatalogError.invalid }
        shows = decoded
    }

    static func fromBundle() throws -> DramaCatalog {
        guard let root = Bundle.main.resourceURL else {
            throw CatalogError.invalid
        }
        return try CatalogImport.offline(root: root.appendingPathComponent("Offline", isDirectory: true))
    }

    func search(_ query: String) -> [Drama] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shows }
        return shows.filter { show in
            [show.title, show.subtitle].contains { $0.localizedStandardContains(query) }
                || show.episodes.contains { episode in
                    episode.title.localizedStandardContains(query) || episode.group?.localizedStandardContains(query) == true
                }
        }
    }
}

enum CatalogError: Error { case invalid }

struct Drama: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let episodes: [Episode]
    let category: String?

    var isLive: Bool { category == "live" }
    var isBundled: Bool { category == "demo" || category == "public" }

    var hasValidEpisodeIDs: Bool {
        var seen = Set<String>()
        return episodes.allSatisfy { episode in
            !episode.id.isEmpty && episode.id.count <= 100 && seen.insert(episode.id).inserted
                && !episode.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && episode.isHTTPS
        }
    }
}

struct Episode: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let streamURL: URL
    let group: String?

    var isHTTPS: Bool { CatalogImport.isHTTPS(streamURL) }
}

struct EpisodeKey: Codable, Hashable {
    let showID: String
    let episodeID: String
}

final class ResumeStore {
    private struct Entry: Codable {
        let key: EpisodeKey
        let seconds: Double
    }

    private let defaults: UserDefaults
    private let capacity: Int
    private let storageKey = "SuperTV.resume.v1"

    init(defaults: UserDefaults = .standard, capacity: Int = 80) {
        self.defaults = defaults
        self.capacity = max(1, min(capacity, 80))
    }

    func position(for key: EpisodeKey) -> Double? {
        entries.first { $0.key == key }?.seconds
    }

    func record(_ seconds: Double, for key: EpisodeKey) {
        guard seconds.isFinite, seconds >= 2 else { return }
        save([Entry(key: key, seconds: seconds)] + entries.filter { $0.key != key })
    }

    func finish(_ key: EpisodeKey) {
        save(entries.filter { $0.key != key })
    }

    private var entries: [Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }

    private func save(_ entries: [Entry]) {
        if let bytes = try? JSONEncoder().encode(Array(entries.prefix(capacity))) {
            defaults.set(bytes, forKey: storageKey)
        }
    }
}

enum CatalogImport: LocalizedError {
    case invalidURL, invalidPlaylist, tooLarge, invalidCatalog, missingSamples

    static let byteLimit = 262_144
    static let maxItems = 160
    static let maxEpisodes = 400

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 HTTPS 链接，不可在地址中嵌入用户名或密码。"
        case .invalidPlaylist: return "未找到可用的 HTTPS 频道。HLS 播放地址请选「单个视频或直播」。"
        case .tooLarge: return "清单或本机片库太大，请删减条目或先移除旧片源。"
        case .invalidCatalog: return "清单格式不正确，或缺少可播放的分集。"
        case .missingSamples: return "应用安装包缺少内置示例视频。"
        }
    }

    static func offline(root: URL) throws -> DramaCatalog {
        let files = (1...2).map { root.appendingPathComponent("demo-episode-\($0).mp4") }
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
        else { throw Self.missingSamples }
        return DramaCatalog(shows: [Drama(
            id: "demo-bip-bop", title: "示例短剧 · 片段演练",
            subtitle: "内置原创合成示例，离线可看。不是红果或其他平台内容。",
            episodes: files.enumerated().map {
                Episode(id: "demo-\($0.offset + 1)", title: "第 \($0.offset + 1) 集", streamURL: $0.element, group: nil)
            }, category: "demo"
        )])
    }

    static var publicFilm: Drama? {
        guard let url = URL(string: "https://video.blender.org/object-storage/web_videos/1be4c93c-1fd2-498d-adc7-50126823033e-480.mp4") else {
            return nil
        }
        return Drama(id: "public-wing-it", title: "开放影片 · WING IT!",
                     subtitle: "(CC) Blender Foundation | studio.blender.org · CC BY 4.0 · 需联网",
                     episodes: [Episode(id: "wing-it-1", title: "正片 · 英文动画短片", streamURL: url, group: nil)],
                     category: "public")
    }

    static func url(_ input: String) throws -> URL {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count <= 4_096, !cleaned.contains(where: { $0.isWhitespace }),
              let url = URL(string: cleaned), isHTTPS(url) else { throw Self.invalidURL }
        return url
    }

    static func isHTTPS(_ url: URL) -> Bool {
        guard url.absoluteString.count <= 4_096,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        return c.scheme?.lowercased() == "https" && c.host?.isEmpty == false
            && c.user == nil && c.password == nil && c.fragment == nil
    }

    static func direct(_ input: String, title: String, live: Bool = false) throws -> Drama {
        let url = try url(input)
        let name = clean(title, fallback: live ? "直播源" : "视频源")
        return Drama(id: "link-" + stableID(url.absoluteString), title: name,
                     subtitle: sourceLabel(url), episodes: [
                        Episode(id: "media", title: name, streamURL: url, group: nil)
                     ], category: live ? "live" : nil)
    }

    static func dramaJSON(_ data: Data, source: URL) throws -> [Drama] {
        guard data.count <= byteLimit else { throw Self.tooLarge }
        let parsed: DramaCatalog
        do { parsed = try DramaCatalog(data: data) }
        catch { throw Self.invalidCatalog }
        guard parsed.shows.count <= maxItems else { throw Self.tooLarge }
        return parsed.shows.map { show in
            Drama(id: "json-" + stableID(source.absoluteString + "|" + show.id),
                  title: clean(show.title, fallback: "短剧"),
                  subtitle: sourceLabel(source),
                  episodes: show.episodes.map {
                    Episode(id: $0.id, title: clean($0.title, fallback: "分集"), streamURL: $0.streamURL, group: nil)
                  }, category: nil)
        }
    }

    static func playlist(_ data: Data, source: URL) throws -> Drama {
        guard data.count <= byteLimit else { throw Self.tooLarge }
        guard let original = String(data: data, encoding: .utf8) else { throw Self.invalidPlaylist }
        let body = original.first == "\u{FEFF}" ? String(original.dropFirst()) : original
        let lines = body.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard lines.first?.hasPrefix("#EXTM3U") == true,
              !lines.contains(where: { $0.hasPrefix("#EXT-X-") }) else { throw Self.invalidPlaylist }
        var meta: (String, String?)?
        var seen = Set<URL>()
        var episodes: [Episode] = []
        for line in lines.dropFirst() {
            if line.hasPrefix("#EXTINF:") {
                let info = String(line.dropFirst(8))
                var quoted = false
                let comma = info.firstIndex { c in
                    if c == "\"" { quoted.toggle() }
                    return c == "," && !quoted
                }
                if let comma {
                    let attrs = info[..<comma]
                    let group = attrs.range(of: "group-title=\"").flatMap { marker in
                        attrs[marker.upperBound...].firstIndex(of: "\"").map { end in
                            String(attrs[marker.upperBound..<end])
                        }
                    }
                    meta = (String(info[info.index(after: comma)...]), group)
                } else { meta = nil }
                continue
            }
            if line.hasPrefix("#") { continue }
            defer { meta = nil }
            guard let meta, let url = URL(string: line, relativeTo: source)?.absoluteURL,
                  isHTTPS(url), seen.insert(url).inserted else { continue }
            guard episodes.count < maxEpisodes else { throw Self.tooLarge }
            episodes.append(Episode(id: "channel-" + stableID(url.absoluteString),
                                    title: clean(meta.0, fallback: "频道"), streamURL: url,
                                    group: meta.1.map { clean($0, fallback: "其他") }))
        }
        guard !episodes.isEmpty else { throw Self.invalidPlaylist }
        return Drama(id: "m3u-" + stableID(source.absoluteString), title: "直播频道 · " + (source.host ?? "自有源"),
                     subtitle: sourceLabel(source), episodes: episodes, category: "live")
    }

    private static func sourceLabel(_ url: URL) -> String { "用户导入 · " + (url.host ?? "HTTPS") }
    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(120))
    }
    private static func stableID(_ value: String) -> String {
        let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

struct CatalogVault {
    let url: URL
    private let archiveLimit = 1_048_576

    func load() throws -> [Drama] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= archiveLimit else { throw CatalogImport.tooLarge }
        let data = try Data(contentsOf: url)
        let values = try JSONDecoder().decode([Drama].self, from: data)
        try validate(values)
        return values
    }

    func save(_ shows: [Drama]) throws {
        try validate(shows)
        let data = try JSONEncoder().encode(shows)
        guard data.count <= archiveLimit else { throw CatalogImport.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private func validate(_ shows: [Drama]) throws {
        guard shows.count <= CatalogImport.maxItems else { throw CatalogImport.tooLarge }
        guard Set(shows.map(\.id)).count == shows.count, shows.allSatisfy({ show in
            !show.id.isEmpty && show.id.count <= 100 && !show.episodes.isEmpty
                && show.episodes.count <= CatalogImport.maxEpisodes && show.hasValidEpisodeIDs
        }) else { throw CatalogImport.invalidCatalog }
    }
}

/// Official share-player entry only. It never resolves raw media URLs.
enum OfficialBilibili {
    static func sharePlayer(_ input: String) -> URL? {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: #"^BV[0-9A-Za-z]{10}$"#, options: .regularExpression) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.bilibili.com"
        components.path = "/player.html"
        components.queryItems = [URLQueryItem(name: "bvid", value: id),
                                 URLQueryItem(name: "autoplay", value: "0")]
        return components.url
    }
}
