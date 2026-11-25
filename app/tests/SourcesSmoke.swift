import Foundation

@main
struct SourcesSmoke {
    static func main() throws {
        let initial = payload(7, host: "video.blender.org", query: "one")
        let next = payload(8, host: "video.blender.org", query: "two")
        let stale = payload(6, host: "video.blender.org")
        let other = payload(9, host: "evil.example")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("supertv-source-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hosts: Set<String> = ["video.blender.org"]
        let store = try ManagedCatalogStore(bundled: initial, cacheURL: tmp, allowedMediaHosts: hosts)
        precondition(store.catalog.revision == 7)
        let oldShow = store.catalog.shows[0]
        precondition(tryApply(store, next))
        precondition(!tryApply(store, next), "Same revision and same content is not an update")
        precondition(store.catalog.shows[0].id == oldShow.id && store.catalog.shows[0].episodes[0].id == oldShow.episodes[0].id)
        precondition(store.catalog.shows[0].episodes[0].streamURL != oldShow.episodes[0].streamURL)
        let new = store.catalog
        reject { try store.apply(stale) }
        reject { try store.apply(other) }
        reject { try store.apply(payload(8, host: "video.blender.org", query: "changed-without-version")) }
        reject { try store.apply(Data("{".utf8)) }
        reject { try store.apply(Data(repeating: 65, count: CatalogImport.byteLimit + 1)) }
        reject { try store.apply(payload(9, host: "video.blender.org", duplicate: true)) }
        reject { try store.apply(payload(9, host: "video.blender.org", schema: 2)) }
        reject { try store.apply(payload(9, host: "video.blender.org", scheme: "http")) }
        reject { try store.apply(payload(9, host: "video.blender.org", port: ":8443")) }
        reject { try store.apply(Data(String(decoding: payload(9, host: "video.blender.org"), as: UTF8.self).replacingOccurrences(of: "clip.mp4", with: "clip.mp4?secret=test").utf8)) }
        let reloaded = try ManagedCatalogStore(bundled: initial, cacheURL: tmp, allowedMediaHosts: hosts)
        precondition(reloaded.catalog.revision == new.revision && reloaded.catalog.shows == new.shows)
        try Data("{".utf8).write(to: tmp)
        let retry = try ManagedCatalogStore(bundled: initial, cacheURL: tmp, allowedMediaHosts: hosts)
        precondition(retry.catalog.revision == 7)
        let barrier = tmp.appendingPathComponent("not-a-directory")
        let unwritable = try ManagedCatalogStore(bundled: initial, cacheURL: barrier, allowedMediaHosts: hosts)
        reject { try unwritable.apply(next) }
        precondition(unwritable.catalog.revision == 7)
        print("PASS: source update preserves stable episode IDs, rejects invalid revisions/URLs and retains the last usable catalog across restart.")
    }

    static func payload(_ revision: Int, host: String, query: String = "initial", duplicate: Bool = false, schema: Int = 1, scheme: String = "https", port: String = "") -> Data {
        let first = #"{"id":"test-1","title":"测试片源","publisher":"Blender Foundation","rightsURL":"https://studio.blender.org/projects/wing-it/pages/licensing/","kind":"vod","episodes":[{"id":"episode-1","title":"正片","streamURL":"\#(scheme)://\#(host)\#(port)/\#(query)/clip.mp4"}]}"#
        let rows = duplicate ? "\(first),\(first)" : first
        return Data(#"{"schemaVersion":\#(schema),"revision":\#(revision),"sources":[\#(rows)]}"#.utf8)
    }

    static func reject(_ body: () throws -> Any) {
        do { _ = try body(); preconditionFailure("Unexpected successful managed update") } catch {}
    }
    static func tryApply(_ store: ManagedCatalogStore, _ data: Data) -> Bool {
        do { return try store.apply(data) } catch { preconditionFailure("Expected valid update: \(error)") }
    }
}
