import SwiftUI

/// The whole app, dressed like Spotify: four plain tabs under a mini player. Used only while the player look is Spotify.
struct SpotifyShell: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    var playerNS: Namespace.ID
    @State private var createOpen = false
    @State private var blendOpen = false

    static let green = Color(hex: "#1ED760")
    static let ground = Color(hex: "#121212")

    private var selected: AppTab {
        switch router.tab {
        case .home, .search: router.tab
        default: .library
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    ZStack {
                        page(.home) { HomePage() }
                        page(.search) { SpotifySearchPage() }
                        page(.library) { SpotifyLibraryPage(createOpen: $createOpen) }
                    }
                    if player.current != nil {
                        SpotifyMiniPlayer().matchedTransitionSource(id: "miniPlayer", in: playerNS)
                            .padding(.horizontal, 8).padding(.bottom, 6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if createOpen {
                    Color.black.opacity(0.72).ignoresSafeArea().onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { createOpen = false } }
                        .transition(.opacity)
                    createCard.padding(.horizontal, 8).padding(.bottom, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.92, anchor: .bottom)).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)))
                }
            }
            tabBar
        }
        .background(Self.ground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.3), value: player.current != nil)
        .sheet(isPresented: $blendOpen) { BlendSheet() }
    }

    /// Every tab stays alive (so scroll positions survive); only the chosen one is seen.
    private func page<C: View>(_ tab: AppTab, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .opacity(selected == tab ? 1 : 0)
            .allowsHitTesting(selected == tab)
            .accessibilityHidden(selected != tab)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem("Home", tab: .home) { on in tabImage(on ? "SPTabHomeOn" : "SPTabHomeOff") }
            tabItem("Search", tab: .search) { _ in tabImage("SPTabSearch") }
            tabItem("Your Library", tab: .library) { on in tabImage(on ? "SPTabLibraryOn" : "SPTabLibraryOff") }
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { createOpen.toggle() }
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 34, height: 34)
                            .scaleEffect(createOpen ? 1 : 0.3).opacity(createOpen ? 1 : 0)
                        tabImage("SPTabCreate")
                            .foregroundStyle(createOpen ? Color.black : Color.white.opacity(0.62))
                            .rotationEffect(.degrees(createOpen ? 45 : 0))
                            .scaleEffect(createOpen ? 0.62 : 1)
                    }
                    .frame(height: 34)
                    Text("Create").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .opacity(createOpen ? 0 : 1)
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .background(Self.ground.opacity(0.98).ignoresSafeArea(edges: .bottom))
    }

    /// The icons are the reference's own pixels (Assets › SPTab…), tinted by the tab's state.
    private func tabImage(_ name: String) -> some View {
        Image(name).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(width: 26, height: 26)
    }

    private func tabItem<I: View>(_ title: String, tab: AppTab, @ViewBuilder icon: (Bool) -> I) -> some View {
        let on = selected == tab && !createOpen
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { createOpen = false }
            if router.tab == tab, tab == .library { router.libraryPath = [] }
            else if router.tab == tab { router.paths[router.tabKey(tab)] = [] }
            router.tab = tab
        } label: {
            VStack(spacing: 3) {
                icon(on).frame(height: 28)
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Color.white.opacity(createOpen ? 0.3 : 0.62))
            .frame(maxWidth: .infinity).frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Create card

    private var createCard: some View {
        VStack(spacing: 0) {
            createRow("music.note", "Playlist", "Create a playlist with songs or episodes") { newPlaylist() }
            createRow("circle.lefthalf.filled", "Blend", "Combine two or more playlists into one") { createOpen = false; blendOpen = true }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#282828")))
    }

    private func createRow(_ symbol: String, _ title: String, _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func newPlaylist() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { createOpen = false }
        let p = library.createPlaylist(name: "My playlist #\(library.playlists.count + 1)")
        router.open(.playlist(p.id))
    }
}

// MARK: - Home

/// Home built from your own music: quick picks, then shelves. The chips filter it.
private struct HomePage: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @State private var filter = 0   // 0 All, 1 Music, 2 Podcasts, 3 Audiobooks

    private func spoken(_ word: String) -> [Track] {
        library.tracks.filter { ($0.genre ?? "").localizedCaseInsensitiveContains(word) }
    }

    private var quick: [(String, LibraryEntry?, Route)] {
        var out: [(String, LibraryEntry?, Route)] = [("Liked Songs", nil, .favorites)]
        for e in library.playlistEntries.prefix(3) { out.append((e.title, e, e.route)) }
        for e in library.albumsByRecent.prefix(8 - out.count) { out.append((e.title, e, e.route)) }
        return Array(out.prefix(8))
    }

    var body: some View {
        NavigationStack(path: Binding(get: { router.paths["home"] ?? [] }, set: { router.paths["home"] = $0 })) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if filter == 2 || filter == 3 {
                        let items = spoken(filter == 2 ? "podcast" : "audiobook")
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Text(filter == 2 ? "No podcasts yet" : "No audiobooks yet").font(.system(size: 20, weight: .bold))
                                Text("Add files tagged with the genre “\(filter == 2 ? "Podcast" : "Audiobook")” and they show up here.")
                                    .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.65)).multilineTextAlignment(.center)
                                Button { router.openAddMusic() } label: {
                                    Text("Add music").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.black)
                                        .padding(.horizontal, 20).frame(height: 40).background(Capsule().fill(Color.white))
                                }.buttonStyle(.plain).padding(.top, 6)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 30)
                        } else {
                            ForEach(items) { t in
                                Button { player.play(items, startAt: items.firstIndex(of: t) ?? 0, title: filter == 2 ? "Podcasts" : "Audiobooks") } label: {
                                    HStack(spacing: 12) {
                                        ArtworkView(track: t, radius: 4).thumbnail().frame(width: 56, height: 56)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                                            Text(t.artist).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(Array(quick.enumerated()), id: \.offset) { _, q in
                                NavigationLink(value: q.2) {
                                    HStack(spacing: 10) {
                                        Group {
                                            if let e = q.1 { ArtworkView(entry: e, radius: 0).thumbnail() }
                                            else { Rectangle().fill(LinearGradient(colors: [Color(hex: "#4F2BFF"), Color(hex: "#A6B4FF")], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay { Image(systemName: "heart.fill").foregroundStyle(Color.white) } }
                                        }
                                        .frame(width: 52, height: 52)
                                        Text(q.0).font(.system(size: 13, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: 52)
                                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.1)))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        shelf("Recents", library.albumsByRecent)
                        shelf("Your playlists", library.playlistEntries)
                        shelf("Your artists", library.artistEntries, circle: true)
                        shelf("Albums by artists you follow", Array(library.albumsByRecent.reversed()))
                        if library.tracks.isEmpty {
                            Text("Add music to fill your Home.").foregroundStyle(Color.white.opacity(0.65)).padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.top, 6).padding(.bottom, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SpotifyAvatar().padding(.trailing, 4)
                        chip("All", 0); chip("Music", 1); chip("Podcasts", 2); chip("Audiobooks", 3)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .background(SpotifyShell.ground)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .background(SpotifyShell.ground)
    }

    @ViewBuilder private func shelf(_ title: String, _ entries: [LibraryEntry], circle: Bool = false) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 21, weight: .bold)).padding(.horizontal, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(entries.prefix(20)) { e in
                            NavigationLink(value: e.route) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(entry: e, radius: circle ? 0 : 4).thumbnail(320).frame(width: 140, height: 140)
                                    Text(e.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                    Text(circle ? "Artist" : e.subtitle).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(2)
                                }
                                .frame(width: 140, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func chip(_ title: String, _ i: Int) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { filter = (filter == i && i != 0) ? 0 : i } } label: {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filter == i ? Color.black : Color.white)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(filter == i ? SpotifyShell.green : Color.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}

/// Blend: pick playlists and get one new playlist with songs from each, interleaved.
private struct BlendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            List(library.playlistEntries) { e in
                Button {
                    if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
                } label: {
                    HStack {
                        ArtworkView(entry: e, radius: 4).thumbnail().frame(width: 44, height: 44)
                        Text(e.title)
                        Spacer()
                        if picked.contains(e.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(SpotifyShell.green) }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if library.playlistEntries.count < 2 { Text("Make at least two playlists to blend them.").foregroundStyle(.secondary).padding() } }
            .navigationTitle("Blend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(picked.count < 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .environment(\.colorScheme, .dark)
    }

    private func create() {
        let lists = library.playlistEntries.filter { picked.contains($0.id) }.map { $0.tracks.shuffled() }
        var ids: [UUID] = []
        var seen = Set<UUID>()
        var i = 0
        while ids.count < lists.reduce(0, { $0 + $1.count }) {
            var added = false
            for l in lists where i < l.count { added = true; if seen.insert(l[i].id).inserted { ids.append(l[i].id) } }
            if !added { break }
            i += 1
        }
        let p = library.createPlaylist(name: "Blend", trackIDs: ids)
        dismiss()
        router.open(.playlist(p.id))
    }
}

// MARK: - Search

private struct SpotifySearchPage: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @FocusState private var focused: Bool

    private static let palette = ["#E13300", "#8D67AB", "#1E3264", "#148A08", "#E91429", "#BA5D07", "#509BF5", "#E8115B", "#477D95", "#D84000", "#7358FF", "#2D46B9"]

    private var searching: Bool { focused || !router.searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var genres: [(String, Track)] {
        var seen: [String: [Track]] = [:]
        for t in library.tracks { if let g = t.genre, !g.trimmingCharacters(in: .whitespaces).isEmpty { seen[g, default: []].append(t) } }
        return seen.sorted { $0.value.count > $1.value.count }.compactMap { k, v in v.first.map { (k, $0) } }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: Binding(get: { router.paths["search"] ?? [] }, set: { router.paths["search"] = $0 })) {
            Group {
                if searching {
                    SearchView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVGrid(columns: cols, spacing: 12) {
                                tile("Songs", 0, library.tracks.first, .songs)
                                tile("Albums", 3, library.albumEntries.first?.tracks.first, .albums)
                                tile("Artists", 2, library.artistEntries.first?.tracks.first, .artists)
                                tile("Playlists", 1, library.playlistEntries.first?.tracks.first, .playlists)
                            }
                            if !genres.isEmpty {
                                Text("Browse all").font(.system(size: 18, weight: .bold)).padding(.top, 6)
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(Array(genres.enumerated()), id: \.offset) { i, g in
                                        tile(g.0, i + 4, g.1, nil)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .background(SpotifyShell.ground)
    }

    private var cols: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }

    private var header: some View {
        @Bindable var router = router
        return VStack(spacing: 10) {
            if !searching {
                HStack(spacing: 10) {
                    SpotifyAvatar()
                    Text("Search").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Image(systemName: "camera").font(.system(size: 21))
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.black)
                TextField("", text: $router.searchText, prompt: Text("What do you want to listen to?").foregroundColor(Color.black.opacity(0.62)))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.black).tint(Color.black)
                    .focused($focused).submitLabel(.search).autocorrectionDisabled()
                if searching {
                    Button { router.searchText = ""; focused = false } label: {
                        Text("Cancel").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                    }
                }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(SpotifyShell.ground)
        .animation(.smooth(duration: 0.25), value: searching)
    }

    private func tile(_ title: String, _ index: Int, _ track: Track?, _ route: Route?) -> some View {
        let color = Color(hex: Self.palette[index % Self.palette.count])
        let body = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white).padding(12).lineLimit(2)
            if let track {
                ArtworkView(track: track, radius: 4).thumbnail()
                    .frame(width: 66, height: 66)
                    .rotationEffect(.degrees(25))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .offset(x: 120, y: 54)
            }
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        return Group {
            if let route {
                NavigationLink(value: route) { body }.buttonStyle(.plain)
            } else {
                Button { router.searchText = title; focused = true } label: { body }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Your Library

private struct SpotifyLibraryPage: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Binding var createOpen: Bool
    @State private var kind = "Playlists"

    private var entries: [LibraryEntry] {
        switch kind { case "Artists": library.artistEntries; case "Albums": library.albumEntries; default: library.playlistEntries }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.libraryPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(["Playlists", "Artists", "Albums"], id: \.self) { c in
                            Button { withAnimation(.smooth(duration: 0.2)) { kind = kind == c ? "Playlists" : c } } label: {
                                Text(c).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(kind == c ? Color.black : Color.white)
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(Capsule().fill(kind == c ? SpotifyShell.green : Color.white.opacity(0.12)))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 6)
                    HStack {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .semibold))
                        Text("Recents").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "square.grid.2x2").font(.system(size: 16))
                    }
                    .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 10)

                    NavigationLink(value: Route.favorites) {
                        row(AnyView(SPLibraryHeart()), "Liked Songs", pin: true, "Playlist • \(songCount(library.tracks.filter(\.isFavorite).count))")
                    }.buttonStyle(.plain)
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.route) {
                            row(AnyView(ArtworkView(entry: entry, radius: 4).thumbnail().frame(width: 64, height: 64)), entry.title, pin: false, "\(kind == "Artists" ? "Artist" : kind == "Albums" ? "Album" : "Playlist") • \(songCount(entry.tracks.count))")
                        }.buttonStyle(.plain)
                    }
                    NavigationLink(value: Route.artists) { addRow("Add artists", circle: true) }.buttonStyle(.plain)
                    Button { router.openAddMusic() } label: { addRow("Add podcasts", circle: false) }.buttonStyle(.plain)
                    NavigationLink(value: Route.radio) { addRow("Add events & venues", circle: false) }.buttonStyle(.plain)
                    Button { router.showSongListImport = true } label: { addRow("Import your music", circle: false, symbol: "square.and.arrow.down") }.buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    SpotifyAvatar()
                    Text("Your Library").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Image(systemName: "magnifyingglass").font(.system(size: 22))
                    Button { withAnimation(.smooth(duration: 0.28)) { createOpen.toggle() } } label: {
                        Image(systemName: "plus").font(.system(size: 24, weight: .light)).frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(SpotifyShell.ground)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .background(SpotifyShell.ground)
    }

    private func row(_ art: AnyView, _ title: String, pin: Bool, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            art.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                HStack(spacing: 5) {
                    if pin { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(SpotifyShell.green).rotationEffect(.degrees(45)) }
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func addRow(_ title: String, circle: Bool, symbol: String = "plus") -> some View {
        HStack(spacing: 14) {
            ZStack {
                if circle { Circle().fill(Color.white.opacity(0.1)) }
                else { RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.1)) }
                Image(systemName: symbol).font(.system(size: symbol == "plus" ? 26 : 20, weight: .light)).foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(width: 64, height: 64)
            Text(title).font(.system(size: 16, weight: .bold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct SPLibraryHeart: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#4F2BFF"), Color(hex: "#A6B4FF")], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(Color.white) }
    }
}

/// Spotify's profile bubble.
struct SpotifyAvatar: View {
    @Environment(Router.self) private var router
    /// Your name, set by long-pressing the bubble. Empty until you set it, then a person icon shows.
    @AppStorage("spotifyProfileName") private var name = ""
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Button { router.showSettings = true } label: {
            ZStack {
                Circle().fill(Color(hex: "#F0592B"))
                if let c = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(c).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.black)
                } else {
                    Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(Color.black)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in draft = name; editing = true })
        .alert("Your name", isPresented: $editing) {
            TextField("Name", text: $draft)
            Button("Save") { name = draft }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Shown on the bubble. Tap the bubble for Settings.") }
        .accessibilityLabel("Settings")
    }
}

// MARK: - Mini player

/// Spotify's mini player: the cover, the song, connect, add, play; a thin progress line along the bottom.
struct SpotifyMiniPlayer: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let track = player.current {
            let live = library.trackByID[track.id] ?? track
            let tint = ArtworkCache.tint(for: track)
            HStack(spacing: 10) {
                ArtworkView(track: track, radius: 4).thumbnail().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(SpotifyShell.green).frame(width: 13, height: 13)
                            .overlay { Image(systemName: "sparkle").font(.system(size: 7, weight: .black)).foregroundStyle(Color.black.opacity(0.8)) }
                        Text(track.artist).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image("ConnectGlyph").renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24).foregroundStyle(Color.white.opacity(0.9))
                Button { library.toggleFavorite(live) } label: {
                    ZStack {
                        if live.isFavorite {
                            Circle().fill(SpotifyShell.green)
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(white: 0.16))
                        } else {
                            Circle().strokeBorder(Color.white, lineWidth: 1.8)
                            Image(systemName: "plus").font(.system(size: 14, weight: .regular)).foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 26, height: 26).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 24)).foregroundStyle(Color.white)
                        .frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transaction { $0.animation = nil }
            }
            .padding(.leading, 6).padding(.trailing, 6).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.mix(with: Color.black, by: 0.25)))
            .overlay(alignment: .bottom) { SpotifyMiniProgress().padding(.horizontal, 8).padding(.bottom, 3) }
            .contentShape(Rectangle())
            .onTapGesture { router.showPlayer = true }
            .miniPlayerSwipes()
        }
    }
}

private struct SpotifyMiniProgress: View {
    @Environment(PlayerModel.self) private var player
    var body: some View {
        let f = player.duration > 0 ? min(1, max(0, player.position / player.duration)) : 0
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28))
                Capsule().fill(Color.white).frame(width: g.size.width * f)
            }
        }
        .frame(height: 2)
    }
}
