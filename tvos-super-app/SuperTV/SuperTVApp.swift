import Foundation
import SwiftUI

@main
struct SuperTVApp: App {
    var body: some Scene {
        WindowGroup { CatalogScreen() }
    }
}

struct CatalogScreen: View {
    private let catalog = try? DramaCatalog.fromBundle()
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Apple TV · 短剧原型", systemImage: "tv")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Text("短剧放映厅").font(.largeTitle.weight(.bold))
                        Text("当前仅内置 Apple 官方测试素材。红果、B 站与电视直播尚未接入。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 24) {
                        Button(searching ? "关闭搜索" : "搜索剧名") {
                            searching.toggle()
                            searchFocused = searching
                            if !searching { query = "" }
                        }
                        if searching {
                            TextField("输入剧名", text: $query)
                                .focused($searchFocused)
                                .accessibilityLabel("搜索剧名")
                            if !query.isEmpty {
                                Button("清空") { query = ""; searchFocused = true }
                            }
                        }
                    }
                    if let catalog {
                        let results = catalog.search(query)
                        if results.isEmpty {
                            Label("没有找到匹配的剧名", systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results) { show in
                            NavigationLink(value: show) {
                                ShowRow(show: show)
                            }
                        }
                    } else {
                        Label("无法载入内置演示目录", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 72)
                .padding(.vertical, 48)
            }
            .navigationDestination(for: Drama.self) { DetailScreen(show: $0) }
        }
    }
}

struct ShowRow: View {
    let show: Drama
    var body: some View {
        HStack(spacing: 28) {
            Image(systemName: "film")
                .font(.title)
                .frame(width: 100, height: 100)
                .background(.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(show.title).font(.title3.weight(.semibold))
                Text(show.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(show.episodes.count) 集").font(.callout)
        }
        .padding(14)
    }
}

private struct PlaybackChoice: Identifiable {
    let episode: Episode
    let startAt: Double?
    var id: String { episode.id }
}

struct DetailScreen: View {
    let show: Drama
    private let store = ResumeStore()
    @State private var selection: PlaybackChoice?
    @State private var displayedPositions: [String: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(show.title).font(.largeTitle.weight(.bold))
                Text(show.subtitle).foregroundStyle(.secondary)
                Text("分集").font(.title3.weight(.semibold))
                ForEach(show.episodes) { episode in
                    HStack(spacing: 24) {
                        Button {
                            selection = PlaybackChoice(episode: episode, startAt: displayedPositions[episode.id])
                        } label: {
                            Label(episode.title, systemImage: "play.fill")
                        }
                        if let position = displayedPositions[episode.id] {
                            Text("从 \(timestamp(position)) 继续")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("从头播放") { selection = PlaybackChoice(episode: episode, startAt: nil) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 72)
            .padding(.vertical, 48)
        }
        .onAppear(perform: reloadPositions)
        .fullScreenCover(item: $selection, onDismiss: reloadPositions) { choice in
            PlaybackScreen(
                episode: choice.episode,
                episodeKey: EpisodeKey(showID: show.id, episodeID: choice.episode.id),
                resumeAt: choice.startAt,
                store: store
            )
        }
    }

    private func reloadPositions() {
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
