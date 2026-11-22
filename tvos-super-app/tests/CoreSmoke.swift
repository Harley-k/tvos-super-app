import Foundation

@main
struct CoreSmoke {
    static func main() throws {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try DramaCatalog(data: Data(contentsOf: file))
        let show = try require(catalog.shows.first)
        let first = try require(show.episodes.first)
        let second = try require(show.episodes.dropFirst().first)
        let defaults = try require(UserDefaults(suiteName: "SuperTV-tests-\(UUID())"))
        let store = ResumeStore(defaults: defaults, capacity: 2)
        let one = EpisodeKey(showID: show.id, episodeID: first.id)
        let two = EpisodeKey(showID: show.id, episodeID: second.id)
        let sameEpisodeOtherShow = EpisodeKey(showID: "another-show", episodeID: first.id)
        precondition(catalog.search(" bIp BoP ").contains(show))
        precondition(catalog.search("找不到这部").isEmpty)
        store.record(22, for: one)
        store.record(0, for: one)
        precondition(store.position(for: one) == 22)
        precondition(store.position(for: two) == nil)
        precondition(store.position(for: sameEpisodeOtherShow) == nil)
        precondition(ResumeStore(defaults: defaults).position(for: one) == 22)
        store.record(9, for: two)
        store.record(11, for: sameEpisodeOtherShow)
        precondition(store.position(for: one) == nil)
        store.finish(sameEpisodeOtherShow)
        precondition(store.position(for: sameEpisodeOtherShow) == nil && store.position(for: two) == 9)
        store.record(.infinity, for: two)
        precondition(store.position(for: two) == 9)
        print("PASS: 搜索、按剧/集隔离、进度回读、无效进度、容量上限、看完清理")
    }
    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "CoreSmoke", code: 1) }
        return value
    }
}
