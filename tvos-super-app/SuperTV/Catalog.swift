import Foundation

struct DramaCatalog {
    let shows: [Drama]
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
        guard let url = Bundle.main.url(forResource: "DemoCatalog", withExtension: "json") else {
            throw CatalogError.invalid
        }
        return try DramaCatalog(data: Data(contentsOf: url))
    }

    func search(_ query: String) -> [Drama] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return shows }
        return shows.filter { [$0.title, $0.subtitle].contains { $0.localizedStandardContains(query) } }
    }
}

enum CatalogError: Error { case invalid }

struct Drama: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let episodes: [Episode]

    fileprivate var hasValidEpisodeIDs: Bool {
        var seen = Set<String>()
        return episodes.allSatisfy { episode in
            !episode.id.isEmpty && episode.id.count <= 100 && seen.insert(episode.id).inserted
                && !episode.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && episode.isHTTPS
        }
    }
}

struct Episode: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let streamURL: URL

    fileprivate var isHTTPS: Bool {
        guard let components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)
        else { return false }
        return components.scheme?.lowercased() == "https" && components.host?.isEmpty == false
            && components.user == nil && components.password == nil
    }
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
