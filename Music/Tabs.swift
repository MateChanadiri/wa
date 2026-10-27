import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// ... (Keep everything from the top of your file exactly the same up to `struct SearchView`) ...

// MARK: - Search

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(LayoutStore.self) private var layout

    private var query: String { router.searchText }
    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    
    @State private var aiFilter: SmartFilter?
    @State private var aiFor = ""
    @State private var openCategory: ModuleCategory?
    @State private var moduleResults: [(InstalledModule, [ModuleTrack])] = []
    @State private var moduleLoading = false
    
    // FIXED: Moved heavy computation out of body to prevent freeze
    @State private var smartSongs: [Track] = []
    @State private var lyricHits: [Track] = []

    private var smartFilter: SmartFilter? {
        guard q.count >= 3 else { return nil }
        let f = SmartSearch.parse(q, artists: library.memo("search.artists") { library.artistEntries.map(\.title) },
                                  albums: library.memo("search.albums") { library.albumEntries.map(\.title) },
                                  genres: library.memo("search.genres") { Array(Set(library.tracks.compactMap(\.genre))) })
        if f.isStructured { return f }
        return aiFor == q ? aiFilter : nil
    }

    // Spotify-style categories
    private static let categories: [String] = ["Made for You", "New Releases", "Pop", "Hip-Hop", "Rock", "Chill", "Workout", "R&B", "Dance", "Indie", "Jazz", "Classical", "K-Pop", "Sleep", "Focus", "Party"]

    private var categoryGrid: some View {
        let remote: [ModuleCategory] = ModuleStore.shared.categories
        let fallback: [String] = Self.categories
        let have: Set<String> = Set(remote.map { $0.name.lowercased() })
        let extra: [(name: String, query: String)] = NonStopStations.all.filter { !have.contains($0.name.lowercased()) }
        
        let colors: [Color] = [.red, .blue, .purple, .pink, .orange, .green, .teal, .indigo]
        
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            CategoryTile(name: "Music Radio")
                .contentShape(Rectangle())
                .onTapGesture { router.open(.radio) }
            if remote.isEmpty {
                ForEach(Array(fallback.enumerated()), id: \.offset) { index, name in
                    Button { router.searchText = name } label: {
                        Text(name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .frame(height: 100)
                            .background(colors[index % colors.count])
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(remote) { (cat: ModuleCategory) in
                    CategoryTile(name: cat.name, image: cat.image)
                        .contentShape(Rectangle())
                        .onTapGesture { openCategory = cat }
                }
                ForEach(extra, id: \.name) { st in
                    StationTile(name: st.name, query: st.query, height: 104)
                        .contentShape(Rectangle())
                        .onTapGesture { router.searchText = st.query }
                }
            }
        }
    }

    private func matches(_ s: String) -> Bool { s.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }

    private var connected: Bool { NetworkMonitor.shared.isOnline && !settings.offlineMode }

    private var idle: (title: String, tracks: [Track]) {
        guard connected else {
            return ("On This iPhone", Array(library.tracks.filter(\.isOffline).sorted { $0.addedAt > $1.addedAt }.prefix(25)))
        }
        let top = library.mostPlayed
        if top.isEmpty { return ("Recently Added", Array(library.tracks.sorted { $0.addedAt > $1.addedAt }.prefix(25))) }
        return ("Most Played", Array(top.prefix(20)))
    }

    private var suggested: [ModuleTrack] {
        guard connected, layout.visibleSections.contains(.suggested) else { return [] }
        return Array(library.newToYou(ModuleStore.shared.suggestions.flatMap(\.tracks)).prefix(10))
    }

    var body: some View {
        let start = q.isEmpty ? self.idle : (title: "", tracks: [Track]())
        let picks = q.isEmpty ? self.suggested : []
        let songs = q.isEmpty ? start.tracks
                              : library.tracks.filter { matches($0.title) || matches($0.artist) || matches($0.album) }
        let artists = q.isEmpty ? [] : library.artistEntries.filter { matches($0.title) }
        let albums = q.isEmpty ? [] : library.albumEntries.filter { matches($0.title) || matches($0.subtitle) }
        let playlists = q.isEmpty ? [] : library.playlistEntries.filter { matches($0.title) }
        let moduleArtists = q.isEmpty ? [] : moduleArtistNames(excluding: artists.map(\.title))

        List {
            if q.isEmpty {
                Section {
                    categoryGrid
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Browse All").font(.system(size: 22, weight: .bold)).textCase(nil).foregroundStyle(.primary)
                }
            }
            if let smart = smartFilter, !smartSongs.isEmpty {
                Section {
                    PlayShuffleBar(tracks: smartSongs, title: smart.summary)
                        .listRowSeparator(.hidden)
                    ForEach(smartSongs.prefix(100)) { track in
                        TrackRow(track: track) {
                            player.play(smartSongs, startAt: smartSongs.firstIndex(of: track) ?? 0, title: smart.summary)
                        }
                    }
                } header: {
                    Label(smart.summary, systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .textCase(nil)
                }
            }
            if !artists.isEmpty || !moduleArtists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { link($0) }
                    ForEach(moduleArtists, id: \.self) { name in
                        NavigationLink {
                            ModuleArtistView(name: name).themedBackground()
                        } label: {
                            Label(name, systemImage: "music.mic").font(.system(size: 16, weight: .medium)).lineLimit(1)
                        }
                    }
                }
            }
            if !albums.isEmpty {
                Section("Albums") { ForEach(albums) { link($0) } }
            }
            if !playlists.isEmpty {
                Section("Playlists") { ForEach(playlists) { link($0) } }
            }
            if !q.isEmpty { ModuleSearchSection(results: moduleResults, loading: moduleLoading) }
            if !picks.isEmpty {
                Section("Suggested for You") {
                    ForEach(picks) { t in ModuleResultRow(track: t, others: picks) }
                }
            }
            if !lyricHits.isEmpty {
                Section("In Lyrics") {
                    ForEach(lyricHits) { track in
                        TrackRow(track: track) { player.play(lyricHits, startAt: lyricHits.firstIndex(of: track) ?? 0, title: "Search") }
                    }
                }
            }
            if !songs.isEmpty {
                Section(q.isEmpty ? start.title : "Songs") {
                    ForEach(songs) { track in
                        TrackRow(track: track) {
                            player.play(songs, startAt: songs.firstIndex(of: track) ?? 0, title: q.isEmpty ? start.title : "Search")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Search")
        .navigationDestination(item: $openCategory) { (cat: ModuleCategory) in CategoryTracksView(category: cat) }
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if !q.isEmpty && songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty && smartFilter == nil && lyricHits.isEmpty
                && moduleResults.isEmpty && !moduleLoading {
                ContentUnavailableView.search(text: q)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        .task(id: q) { await searchModules() }
        .task { await ModuleStore.shared.refreshDiscovery() }
        .task(id: connected) {
            guard connected, layout.visibleSections.contains(.suggested) else { return }
            await ModuleStore.shared.refreshSuggestions(seeds: Array(library.mostPlayed.prefix(10)))
        }
        // FIXED: Debounced search logic to prevent freeze
        .task(id: q) {
            if q.count < 3 {
                smartSongs = []
                lyricHits = []
                aiFilter = nil
                return
            }
            
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            
            // 1. Smart Filter
            if let smart = smartFilter {
                smartSongs = SmartSearch.apply(smart, to: library.tracks)
            } else {
                smartSongs = []
            }
            
            // 2. Lyrics Search
            if q.count >= 4 {
                let songIDs = Set(smartSongs.map(\.id))
                lyricHits = Array(library.tracks.lazy.filter { t in
                    !songIDs.contains(t.id) && (t.lyrics.map { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil } ?? false)
                }.prefix(20))
            } else {
                lyricHits = []
            }
            
            // 3. AI Fallback
            if smartFilter == nil, q.split(separator: " ").count >= 3, SmartSearchAI.available {
                let current = q
                let result = await SmartSearchAI.interpret(current, artists: library.artistEntries.map(\.title), genres: Array(Set(library.tracks.compactMap(\.genre))))
                if !Task.isCancelled { aiFilter = result; aiFor = current }
            }
        }
    }

    private func moduleArtistNames(excluding own: [String]) -> [String] {
        let have = Set(own.map(SmartSearch.norm))
        var seen = Set<String>(), out: [String] = []
        for (_, tracks) in moduleResults {
            for t in tracks where t.artist != "Unknown Artist" && matches(t.artist) {
                let k = SmartSearch.norm(t.artist)
                if !have.contains(k), seen.insert(k).inserted { out.append(t.artist) }
            }
        }
        return Array(out.prefix(5))
    }

    private func searchModules() async {
        let current = q
        guard current.count >= 3, ModuleStore.shared.hasSearchModules else { moduleResults = []; moduleLoading = false; return }
        moduleLoading = true
        try? await Task.sleep(for: .milliseconds(650))
        if Task.isCancelled { return }
        let found = await ModuleStore.shared.search(current, limit: 15)
        if Task.isCancelled { return }
        moduleResults = found
        moduleLoading = false
    }

    private func link(_ e: LibraryEntry) -> some View {
        NavigationLink(value: e.route) {
            HStack(spacing: 12) {
                ArtworkView(entry: e, radius: 8).thumbnail().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text(e.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

// ... (Keep SettingsView, LyricsSourceSections, ConnectionsView from top of original file) ...
