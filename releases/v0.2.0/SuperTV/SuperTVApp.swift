import Foundation
import SwiftUI
#if os(macOS)
import WebKit
#endif

@main
struct SuperTVApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup { CatalogScreen().frame(minWidth: 720, minHeight: 520) }
            .defaultSize(width: 1060, height: 680)
        #else
        WindowGroup { CatalogScreen() }
        #endif
    }
}

enum TrialDefaults {
    static var debugSuite: String? {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["SUPERTV_UI_TEST_SUITE"],
           name.hasPrefix("SuperTV.UI."), UUID(uuidString: String(name.dropFirst("SuperTV.UI.".count))) != nil {
            return name
        }
        #endif
        return nil
    }
    static var playback: UserDefaults {
        debugSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    static var libraryURL: URL {
        #if os(macOS)
        let directory = FileManager.SearchPathDirectory.applicationSupportDirectory
        #else
        let directory = FileManager.SearchPathDirectory.cachesDirectory
        #endif
        let root = FileManager.default.urls(for: directory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(debugSuite ?? "SuperTV", isDirectory: true).appendingPathComponent("Library.json")
    }
}

@MainActor
private final class LibraryModel: ObservableObject {
    @Published private(set) var imported: [Drama] = []
    @Published private(set) var warning: String?
    @Published var query = ""
    private let demo = try? DramaCatalog.fromBundle()
    private let vault = CatalogVault(url: TrialDefaults.libraryURL)

    init() {
        do { imported = try vault.load() }
        catch { warning = "自有片库读取失败，仍可播放内置示例。重新导入可建立新片库。" }
        if demo == nil { warning = "此安装包缺少离线示例。" }
    }

    var results: [Drama] {
        var rows = (demo?.shows ?? []) + [CatalogImport.publicFilm].compactMap { $0 } + imported
        #if DEBUG
        if let suite = TrialDefaults.debugSuite, ProcessInfo.processInfo.environment["SUPERTV_UI_BAD_MEDIA"] == "1" {
            let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
                .appendingPathComponent("intentionally-missing.mp4")
            rows.append(Drama(id: "ui-missing-media", title: "测试故障片源", subtitle: "DEBUG 实际缺失文件",
                episodes: [Episode(id: "ui-missing-media-first", title: "第 1 集",
                                   streamURL: missingURL, group: nil)], category: "demo"))
        }
        #endif
        return DramaCatalog(shows: rows).search(query)
    }

    func insert(_ shows: [Drama]) throws {
        let ids = Set(shows.map(\.id))
        let next = imported.filter { !ids.contains($0.id) } + shows
        try vault.save(next)
        imported = next
        warning = nil
    }

    func remove(_ id: String) throws {
        let next = imported.filter { $0.id != id }
        try vault.save(next)
        imported = next
    }
}

@MainActor
struct CatalogScreen: View {
    @StateObject private var library = LibraryModel()
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @Namespace private var homeFocus

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Apple TV · 试用 0.2", systemImage: "tv")
                            .font(.callout.weight(.semibold)).foregroundStyle(.cyan)
                        Text("短剧放映厅").font(.largeTitle.weight(.bold))
                        Text("内置离线示例。红果、B 站和电视台节目未内置；可导入你有权使用的片源。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 26) {
                        Button(searching ? "关闭搜索" : "搜索片库") {
                            searching.toggle()
                            searchFocused = searching
                            if !searching { library.query = "" }
                        }
                        NavigationLink { SourceImportScreen(library: library) } label: {
                            Label("导入片源", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("source-import")
                        if searching {
                            TextField("输入剧名或剧集", text: $library.query).focused($searchFocused)
                        }
                    }
                    #if os(macOS)
                    NavigationLink("B 站公开视频（Mac 试验入口）") { MacBilibiliScreen() }
                    #endif
                    if let warning = library.warning {
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.yellow)
                    }
                    if library.results.isEmpty {
                        Label("没有匹配的影片或频道", systemImage: "magnifyingglass").foregroundStyle(.secondary)
                    }
                    ForEach(library.results) { show in
                        NavigationLink(value: show) { ShowRow(show: show) }
                            .accessibilityIdentifier("show-" + show.id)
                            .trialDefaultFocus(show.id == "demo-bip-bop", in: homeFocus)
                    }
                }
                .padding(.horizontal, 72)
                .padding(.vertical, 42)
            }
            .trialFocusScope(homeFocus)
            .navigationDestination(for: Drama.self) { show in
                DetailScreen(show: show) { try library.remove(show.id) }
            }
        }
    }
}

private struct ShowRow: View {
    let show: Drama
    var body: some View {
        HStack(spacing: 26) {
            Image(systemName: show.isLive ? "play.tv" : "film")
                .font(.title2).frame(width: 92, height: 76)
                .background(.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(show.title).font(.title3.weight(.semibold))
                Text(show.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(show.episodes.count) \(show.isLive ? "频道" : "集")").font(.callout)
        }.padding(14)
    }
}

private enum SourceKind: String, CaseIterable, Identifiable {
    case video = "单个视频", live = "单个直播", playlist = "M3U 直播清单", drama = "JSON 短剧清单"
    var id: Self { self }
    var isManifest: Bool { self == .playlist || self == .drama }
}

private final class HTTPSRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(CatalogImport.isHTTPS) == true ? request : nil)
    }
}

@MainActor
private struct SourceImportScreen: View {
    @ObservedObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = SourceKind.video
    @State private var input = ""
    @State private var title = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @Namespace private var importFocus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("导入片源").font(.largeTitle.weight(.bold))
                Text("仅添加自有或获准的 HTTPS 片源。视频通常为 HLS 或 MP4，不需要把地址发给任何第三方。")
                    .foregroundStyle(.secondary)
                Picker("类型", selection: $kind) {
                    ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("输入完整 HTTPS 地址", text: $input)
                    .accessibilityIdentifier("source-url")
                if !kind.isManifest { TextField("名称（选填）", text: $title) }
                if let error {
                    Text(error).foregroundStyle(.yellow).accessibilityIdentifier("source-error")
                }
                Button(task == nil ? "导入" : "正在读取片源…", action: submit)
                    .disabled(task != nil)
                    .accessibilityIdentifier("source-import-submit")
                    .trialDefaultFocus(true, in: importFocus)
                Button("返回") { dismiss() }
            }.padding(64)
        }
        .trialFocusScope(importFocus)
        .onDisappear { task?.cancel(); task = nil }
    }

    private func submit() {
        guard task == nil else { return }
        error = nil
        let url: URL
        do { url = try CatalogImport.url(input) }
        catch { self.error = error.localizedDescription; return }
        let savedKind = kind
        let name = title
        task = Task {
            defer { task = nil }
            do {
                let shows: [Drama]
                if savedKind.isManifest {
                    let (data, finalURL) = try await fetch(url)
                    if savedKind == .playlist {
                        shows = [try CatalogImport.playlist(data, source: finalURL)]
                    } else {
                        shows = try CatalogImport.dramaJSON(data, source: finalURL)
                    }
                } else {
                    shows = [try CatalogImport.direct(url.absoluteString, title: name, live: savedKind == .live)]
                }
                try Task.checkCancellation()
                try library.insert(shows)
                library.query = ""
                dismiss()
            } catch is CancellationError {
                return
            } catch let issue as CatalogImport {
                error = issue.localizedDescription
            } catch {
                self.error = "无法读取或保存片源。请确认地址可访问、内容格式正确，然后重试。"
            }
        }
    }

    private func fetch(_ url: URL) async throws -> (Data, URL) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url, delegate: HTTPSRedirect())
        guard let status = response as? HTTPURLResponse, (200...299).contains(status.statusCode),
              let final = response.url, CatalogImport.isHTTPS(final) else { throw URLError(.badServerResponse) }
        guard response.expectedContentLength <= Int64(CatalogImport.byteLimit) else { throw CatalogImport.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < CatalogImport.byteLimit else { throw CatalogImport.tooLarge }
            data.append(byte)
        }
        return (data, final)
    }
}

private struct PlaybackChoice: Identifiable {
    let episode: Episode
    let startAt: Double?
    var id: String { episode.id }
}

@MainActor
private struct DetailScreen: View {
    let show: Drama
    let remove: () throws -> Void
    private let store = ResumeStore(defaults: TrialDefaults.playback)
    @State private var selection: PlaybackChoice?
    @State private var displayedPositions: [String: Double] = [:]
    @State private var confirmRemove = false
    @State private var removeError = false
    @Environment(\.dismiss) private var dismiss
    @Namespace private var detailFocus

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text(show.title).font(.largeTitle.weight(.bold))
                Text(show.subtitle).foregroundStyle(.secondary)
                if show.category == "public" {
                    Text("官方来源：video.blender.org · 许可：creativecommons.org/licenses/by/4.0/")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(show.isLive ? "直播频道" : "分集").font(.title3.weight(.semibold))
                ForEach(show.episodes) { episode in
                    HStack(spacing: 22) {
                        Button {
                            selection = PlaybackChoice(episode: episode, startAt: displayedPositions[episode.id])
                        } label: {
                            Label(episode.title, systemImage: "play.fill")
                        }
                        .accessibilityIdentifier("episode-" + episode.id)
                        .trialDefaultFocus(episode.id == show.episodes.first?.id, in: detailFocus)
                        if let group = episode.group { Text(group).font(.callout).foregroundStyle(.secondary) }
                        if let position = displayedPositions[episode.id] {
                            Text("从 \(timestamp(position)) 继续")
                                .font(.callout).foregroundStyle(.secondary)
                                .accessibilityIdentifier("resume-" + episode.id)
                            Button("从头播放") { selection = PlaybackChoice(episode: episode, startAt: nil) }
                        }
                    }
                }
                if !show.isBundled {
                    Button(role: .destructive) { confirmRemove = true } label: { Text("移除此片源") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 72).padding(.vertical, 42)
        }
        .trialFocusScope(detailFocus)
        .onAppear(perform: reloadPositions)
        .trialPlaybackPresentation(item: $selection, onDismiss: reloadPositions) { choice in
            PlaybackScreen(episode: choice.episode, episodeKey: EpisodeKey(showID: show.id, episodeID: choice.episode.id),
                           resumeAt: choice.startAt, store: store, isLive: show.isLive)
        }
        .alert("从本机片库移除这个条目？", isPresented: $confirmRemove) {
            Button("移除", role: .destructive) {
                do { try remove(); dismiss() } catch { removeError = true }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("未能保存片库", isPresented: $removeError) { Button("好", role: .cancel) {} }
    }

    private func reloadPositions() {
        guard !show.isLive else { return }
        displayedPositions = Dictionary(uniqueKeysWithValues: show.episodes.compactMap { episode in
            guard let seconds = store.position(for: EpisodeKey(showID: show.id, episodeID: episode.id))
            else { return nil }
            return (episode.id, seconds)
        })
    }

    private func timestamp(_ seconds: Double) -> String {
        let ticks = Int(max(0, min(seconds, 999_999)))
        return String(format: "%d:%02d", ticks / 60, ticks % 60)
    }
}

extension View {
    @ViewBuilder
    func trialPlaybackPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>, onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item, onDismiss: onDismiss) { choice in
            content(choice).frame(minWidth: 720, idealWidth: 960, minHeight: 480, idealHeight: 620)
        }
        #else
        self.fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func trialDefaultFocus(_ preferred: Bool, in scope: Namespace.ID) -> some View {
        #if os(tvOS)
        self.prefersDefaultFocus(preferred, in: scope)
        #else
        self
        #endif
    }

    @ViewBuilder
    func trialFocusScope(_ scope: Namespace.ID) -> some View {
        #if os(tvOS)
        self.focusScope(scope)
        #else
        self
        #endif
    }

    @ViewBuilder
    func trialExitCommand(perform action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }

    @ViewBuilder
    func trialCloseShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }
}

#if os(macOS)
@MainActor
private struct MacBilibiliScreen: View {
    @State private var input = ""
    @State private var url: URL?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("B 站公开视频 · Mac 试验入口").font(.title2.weight(.semibold))
            Text("仅载入 B 站官方分享播放器。只支持允许站外嵌入的公开视频，不含直播、登录或会员专享。")
                .foregroundStyle(.secondary)
            HStack {
                TextField("输入 BV 号", text: $input)
                Button("打开官方播放器") {
                    guard let destination = OfficialBilibili.sharePlayer(input) else {
                        message = "请粘贴完整 BV 号。"
                        return
                    }
                    message = nil
                    url = destination
                }
                .keyboardShortcut(.defaultAction)
            }
            if let message { Text(message).foregroundStyle(.orange) }
            if let url {
                MacOfficialPlayer(url: url) { message = "未能载入官方播放器，播放资格以 B 站页面为准。" }
                    .id(url)
                    .frame(minHeight: 300)
            } else { Spacer() }
        }
        .padding(28)
    }
}

private struct MacOfficialPlayer: NSViewRepresentable {
    let url: URL
    let didFail: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(didFail: didFail) }

    func makeNSView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .nonPersistent()
        settings.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: settings)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let didFail: () -> Void
        init(didFail: @escaping () -> Void) { self.didFail = didFail }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let frame = action.targetFrame, let next = action.request.url,
                  next.scheme == "https" || next.absoluteString == "about:blank" else {
                decisionHandler(.cancel); return
            }
            decisionHandler(!frame.isMainFrame || next.host == "player.bilibili.com" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { didFail() }
        }
    }
}
#endif
