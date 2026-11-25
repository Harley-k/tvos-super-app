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
        let remote = try require(URL(string: "https://media.example/catalog/list.m3u"))
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-name="节目1" group-title="新闻, 海外",频道甲
        ../live/a.m3u8
        #EXTINF:-1,无效频道
        http://unsafe.example/b.m3u8
        #EXTINF:-1,频道甲的重复项
        ../live/a.m3u8
        #EXTINF:-1 group-title="体育",频道乙
        https://media.example/live/b.m3u8
        """
        let live = try CatalogImport.playlist(Data(m3u.utf8), source: remote)
        precondition(live.isLive && live.episodes.map(\.title) == ["频道甲", "频道乙"])
        precondition(live.episodes.first?.group == "新闻, 海外")
        precondition(live.episodes.first?.streamURL.absoluteString == "https://media.example/live/a.m3u8")
        let direct = try CatalogImport.direct("https://media.example/movie.mp4?token=a", title: "自己视频")
        precondition(direct.title == "自己视频" && !direct.isLive)
        let id = direct.id
        let renamed = try CatalogImport.direct("https://media.example/movie.mp4?token=a", title: "改名")
        precondition(renamed.id == id)
        expectRejection { try CatalogImport.direct("https://x:y@media.example/a.mp4", title: "") }
        expectRejection { try CatalogImport.playlist(Data("#EXTM3U\n#EXT-X-TARGETDURATION:10\npart.ts".utf8), source: remote) }
        expectRejection { try CatalogImport.playlist(Data("#EXTM3U\n#EXTINF:-1,坏源\nhttp://a/b".utf8), source: remote) }
        let jsonSource = URL(string: "https://media.example/series.json")!
        let json = #"{"shows":[{"id":"s","title":"测试剧","subtitle":"","episodes":[{"id":"e","title":"第一集","streamURL":"https://media.example/drama/e.mp4"}]}]}"#
        let shows = try CatalogImport.dramaJSON(Data(json.utf8), source: jsonSource)
        precondition(shows.count == 1 && shows[0].id != "s" && shows[0].episodes[0].id == "e")
        func refresh(_ catalogId: String, _ source: String, _ token: String) throws -> Drama {
            let payload = #"{"catalogId":"CID","shows":[{"id":"s","title":"剧","subtitle":"","episodes":[{"id":"e1","title":"一","streamURL":"https://cdn.example/a?key=TOKEN"},{"id":"e2","title":"二","streamURL":"https://cdn.example/b?key=TOKEN"}]}]}"#
                .replacingOccurrences(of: "CID", with: catalogId).replacingOccurrences(of: "TOKEN", with: token)
            return try require(CatalogImport.dramaJSON(Data(payload.utf8), source: URL(string: source)!).first)
        }
        let a = try refresh("library", "https://publisher.example/feed?sig=A", "one")
        let b = try refresh("library", "https://PUBLISHER.EXAMPLE:443/v2?sig=B", "two")
        precondition(a.id == b.id && a.episodes[0].streamURL != b.episodes[0].streamURL)
        store.record(12, for: EpisodeKey(showID: a.id, episodeID: a.episodes[0].id))
        precondition(store.position(for: EpisodeKey(showID: b.id, episodeID: b.episodes[0].id)) == 12)
        precondition(store.position(for: EpisodeKey(showID: b.id, episodeID: b.episodes[1].id)) == nil)
        for other in [try refresh("library", "https://other.example/feed", "two"),
                      try refresh("separate", "https://publisher.example/feed", "two"),
                      try refresh("library", "https://publisher.example:444/feed", "two")] {
            precondition(a.id != other.id)
        }
        expectRejection { try refresh("bad id", "https://publisher.example/feed", "x") }
        expectRejection { try refresh("library", "http://publisher.example/feed", "x") }
        let legacy = try CatalogImport.dramaJSON(Data(json.utf8), source: URL(string: "https://media.example/series.json?instance=2")!)
        precondition(legacy[0].id != shows[0].id && shows[0].id.hasPrefix("json-"))
        print("PASS: stable publisher catalog identity across refresh, isolated episodes/origins/ports/catalogs and old feed behavior")
        let local = try CatalogImport.offline(root: file.deletingLastPathComponent().appendingPathComponent("Offline"))
        precondition(local.shows[0].episodes.count == 2 && local.shows[0].episodes.allSatisfy { $0.streamURL.isFileURL })
        let vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent("supertv-smoke-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let vault = CatalogVault(url: vaultURL)
        try vault.save([direct] + shows + [live])
        let readback = try vault.load()
        precondition(readback == [direct] + shows + [live])
        expectRejection { try vault.save(local.shows) }
        let verified = try vault.load()
        precondition(verified == readback)
        let official = try require(OfficialBilibili.sharePlayer("BV1XP4y1x7yi"))
        precondition(official.host == "player.bilibili.com" && official.scheme == "https")
        precondition(OfficialBilibili.sharePlayer("BV1XP4y1x7yi&autoplay=1") == nil)
        print("PASS: 官方分享播放器 URL 限制")
        print("PASS: M3U/JSON/直链解析、隔离离线资源、持久化")
        print("PASS: 搜索、按剧/集隔离、进度回读、无效进度、容量上限、看完清理")
    }
    static func expectRejection(_ body: () throws -> Any) {
        do { _ = try body(); preconditionFailure("invalid input accepted") } catch {}
    }
    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "CoreSmoke", code: 1) }
        return value
    }
}
