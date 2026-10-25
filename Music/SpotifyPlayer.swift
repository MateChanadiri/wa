import SwiftUI
import Translation
import AVKit
import UIKit

// MARK: - Spotify look
//
// A scrolling player: the first screen is the now-playing page (cover, title, bar, controls), and under it come
// the lyrics preview, about the artist, credits and explore cards. The queue, the "…" menu and the "Saved in"
// card slide up as sheets.

private let spotifyBackground = Color(hex: "#121212")
private let spotifyCard = Color(hex: "#1F1F1F")

/// A button that looks the same pressed and not pressed: Spotify's controls have no press animation.
private struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// What the "…" menu can ask the player screen to do (sheets that live in the screen itself).
struct SPActions {
    var addToPlaylist: () -> Void
    var equalizer: () -> Void
    var editMetadata: () -> Void
    var designCover: () -> Void
    var editLyrics: () -> Void
    var customize: () -> Void
}

struct SpotifyPlayerPage: View {
    let track: Track
    let design: PlayerDesign
    @Binding var queueOpen: Bool
    var close: () -> Void
    var actions: SPActions
    /// The status bar / home bar sizes: the page is laid out on the whole screen, so it pads itself.
    let insets: EdgeInsets

    init(track: Track, design: PlayerDesign, queueOpen: Binding<Bool>, close: @escaping () -> Void, actions: SPActions, insets: EdgeInsets) {
        self.insets = insets
        self.track = track
        self.design = design
        _queueOpen = queueOpen
        self.close = close
        self.actions = actions
    }

    @Environment(PlayerModel.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @Environment(LyricsService.self) private var lyricsService
    @Environment(DownloadManager.self) private var downloads

    @State private var offset: CGFloat = 0
    /// 1: the next song comes in from the right; -1: the previous one comes in from the left.
    @State private var direction: CGFloat = 1
    @State private var songCount = 0
    @State private var plays = 0
    @State private var info: SPArtistInfo?
    @State private var bioOpen = false
    @State private var lyricsOpen = false
    @State private var menuOpen = false
    @State private var savedOpen = false
    @State private var savedTask: Task<Void, Never>?
    @Environment(AppSettings.self) private var settings
    @State private var translations: [Int: String] = [:]
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var timingOpen = false
    @State private var savedDetent: PresentationDetent = .height(230)
    @State private var scrollTarget: String?
    @State private var airplay = AirPlayTrigger()
    /// "Lyrics • On" in the menu: the line being sung shows under the cover.
    @AppStorage("spotifyLyricLine") private var lyricLine = false

    private var accent: Color { design.accentColor(Color(hex: "#1ED760")) }
    private var tint: Color { ArtworkCache.tint(for: track) }
    /// How much of the lyrics card peeks in under the first page, so it's clear the player scrolls.
    private let peek: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                background(geo.size)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            nowPlayingPage(height: max(480, geo.size.height - peek))
                            lyricsCard
                            aboutCard
                            creditsCard.id("credits")
                            exploreCard
                            Color.clear.frame(height: 30)
                        }
                        .frame(width: geo.size.width)
                    }
                    .scrollClipDisabled()
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in offset = new }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }

                if offset > 330 { stickyHeader.transition(.opacity) }

                lyricsPage
                    .offset(y: lyricsOpen ? 0 : geo.size.height + 80)
                    .allowsHitTesting(lyricsOpen)
                    .zIndex(3)
            }
            .animation(.easeOut(duration: 0.2), value: offset > 330)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: track.id) {
            let mine = library.tracks.filter { $0.artist == track.artist }
            songCount = mine.count
            plays = mine.reduce(0) { $0 + ($1.playCount ?? 0) }
            lyricsService.autoDetect(for: library.trackByID[track.id] ?? track)
        }
        .sheet(isPresented: $queueOpen) {
            queueSheet
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $menuOpen) {
            menuSheet
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $savedOpen) {
            savedSheet
                .presentationDetents([.height(230), .large], selection: $savedDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
        .onChange(of: savedDetent) { _, _ in savedTask?.cancel() }
        .task(id: track.artist) {
            info = nil
            bioOpen = false
            info = await SPArtistInfoCache.shared.info(for: SPArtistInfoCache.mainName(track.artist))
        }
    }

    // MARK: Background

    private func background(_ size: CGSize) -> some View {
        // The gradient is an overlay so its extra height never widens or stretches the page.
        spotifyBackground
            .overlay(alignment: .top) {
                LinearGradient(colors: [tint, tint.opacity(0.55), spotifyBackground], startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 1.25)
                    .offset(y: -offset)
            }
            .clipped()
            .ignoresSafeArea()
    }

    // MARK: First page

    private func nowPlayingPage(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar.padding(.horizontal, 16).padding(.top, insets.top + 6).padding(.bottom, 6)
                .contentShape(Rectangle())
                // Only the top strip pulls the player down; the rest of the page just scrolls.
                .gesture(DragGesture(minimumDistance: 16).onEnded { v in
                    if v.translation.height > 70, abs(v.translation.height) > abs(v.translation.width) { close() }
                })

            GeometryReader { g in
                let side: CGFloat = max(60, min(g.size.width - 64, g.size.height - 8))
                ZStack {
                    ArtworkView(track: track, radius: 0)
                        .frame(width: side, height: side)
                        .id(track.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: direction > 0 ? .trailing : .leading),
                            removal: .move(edge: direction > 0 ? .leading : .trailing)))
                }
                .frame(width: g.size.width, height: g.size.height)
                .animation(.easeInOut(duration: 0.28), value: track.id)
            }
            .padding(.vertical, 8)

            if let line = currentLyricLine {
                Text(line)
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 28)
                    .transaction { $0.animation = nil }
            }
            titleRow.padding(.horizontal, 28).transaction { $0.animation = nil }
            SPScrubber(showTimes: design.showTimes).padding(.horizontal, 28).padding(.top, 12)
            controls.padding(.horizontal, 22).padding(.top, 4).transaction { $0.animation = nil }
            bottomRow.padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 12).transaction { $0.animation = nil }
        }
        .frame(height: height)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(StillButtonStyle())
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text("Playing from").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.75))
                Text(player.queueTitle.isEmpty ? track.album : player.queueTitle)
                    .font(.system(size: 12, weight: .bold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { openMenu() } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).frame(width: 40, height: 40)
            }
            .buttonStyle(StillButtonStyle())
        }
        .foregroundStyle(Color.white)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: track.title, centered: false, centerShift: 0)
                    .font(.system(size: 21, weight: .bold))
                MarqueeText(text: track.artist, centered: false, centerShift: 0)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if design.showFavorite { favoriteButton(size: 28) }
        }
    }

    private func favoriteButton(size: CGFloat) -> some View {
        SPLikeButton(on: track.isFavorite, accent: accent, size: size) {
            library.toggleFavorite(track)
            showSaved()
        }
        .accessibilityLabel("Favorite")
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.setShuffle(!player.shuffle) } label: {
                VStack(spacing: 4) {
                    SPGlyph(kind: .shuffle, color: player.shuffle ? accent : Color.white).frame(width: 24, height: 24)
                    Circle().fill(accent).frame(width: 4, height: 4).opacity(player.shuffle ? 1 : 0)
                }
                .frame(width: 52, height: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(StillButtonStyle())
            Spacer(minLength: 0)
            Button { skip(-1) } label: {
                SPSkip(forward: false).frame(width: 26, height: 26).frame(width: 56, height: 58)
            }
            .buttonStyle(StillButtonStyle())
            Spacer(minLength: 0)
            Button { player.togglePlay() } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 62, height: 62)
                    SPPlayPause(isPlaying: player.isPlaying, color: Color.black.opacity(0.78)).frame(width: 28, height: 28)
                }
                .frame(width: 66, height: 66)
                .contentShape(Rectangle())
            }
            .buttonStyle(StillButtonStyle())
            Spacer(minLength: 0)
            Button { skip(1) } label: {
                SPSkip(forward: true).frame(width: 26, height: 26).frame(width: 56, height: 58)
            }
            .buttonStyle(StillButtonStyle())
            Spacer(minLength: 0)
            Button { player.cycleRepeat() } label: {
                let on = player.repeatMode != .off
                VStack(spacing: 4) {
                    SPGlyph(kind: .repeatAll, color: on ? accent : Color.white)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if player.repeatMode == .one {
                                Text("1").font(.system(size: 8, weight: .heavy)).foregroundStyle(accent)
                            }
                        }
                    Circle().fill(accent).frame(width: 4, height: 4).opacity(on ? 1 : 0)
                }
                .frame(width: 52, height: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(StillButtonStyle())
        }
    }

    /// The cover slides out and the next one in; the direction is set a moment before the song changes so
    /// the leaving cover already knows which way to go.
    private func skip(_ way: CGFloat) {
        direction = way
        Task {
            try? await Task.sleep(for: .milliseconds(30))
            if way > 0 { player.next() } else { player.previous() }
            try? await Task.sleep(for: .milliseconds(600))
            direction = 1
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button { airplay.fire() } label: {
                ConnectIcon().frame(width: 28, height: 28).frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(StillButtonStyle())
            .background(AirPlayLauncher(trigger: airplay).frame(width: 44, height: 44).opacity(0.02).allowsHitTesting(false))
            Spacer(minLength: 0)
            ShareLink(item: ShareItem.text(for: track), subject: Text(track.title)) {
                SPGlyph(kind: .share, color: Color.white).frame(width: 24, height: 24).frame(width: 44, height: 44)
            }
            Button { queueOpen = true } label: {
                SPGlyph(kind: .queue, color: Color.white).frame(width: 24, height: 24).frame(width: 44, height: 44)
            }
            .buttonStyle(StillButtonStyle())
        }
    }

    // MARK: Sticky header

    private var stickyHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(track.artist).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 0)
            favoriteButton(size: 26)
            Button { player.togglePlay() } label: {
                SPPlayPause(isPlaying: player.isPlaying, color: Color.white).frame(width: 22, height: 22).frame(width: 34, height: 34)
            }
            .buttonStyle(StillButtonStyle())
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.top, insets.top + 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .transaction { $0.animation = nil }
        .background(tint.opacity(0.96))
    }

    // MARK: Cards

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(spotifyCard))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
    }

    private var lyricsCard: some View {
        let lines = LyricsParser.parse(track.lyrics ?? "").filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        var current = 0
        for (i, l) in lines.enumerated() { if let t = l.time, t <= player.position + 0.3 { current = i } }
        let shown = Array(lines.dropFirst(current).prefix(4))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Lyrics preview").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white.opacity(0.75))
            if shown.isEmpty {
                Text(lyricsStatus ?? "No lyrics for this song yet.").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white.opacity(0.8))
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white.opacity(index == 3 ? 0.4 : 1))
                        .multilineTextAlignment(.leading)
                }
            }
            Button { openLyrics(find: shown.isEmpty) } label: {
                Text(shown.isEmpty ? "Find lyrics" : "Show lyrics")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(StillButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.92)))
        .padding(.horizontal, 12)
    }

    /// What the lyric search is doing right now, when it is doing something.
    private var lyricsStatus: String? {
        switch lyricsService.state(track.id) {
        case .running(let message): message
        case .failed(let message): message
        case .notFound: "No lyrics found for this song."
        case nil: nil
        }
    }

    /// The line being sung right now, shown under the cover like Spotify does (only for timed lyrics).
    private var currentLyricLine: String? {
        guard lyricLine, let lyrics = track.lyrics, LyricsParser.isTimed(lyrics) else { return nil }
        var found: String?
        for l in LyricsParser.parse(lyrics) {
            guard let t = l.time else { continue }
            if t <= player.position + 0.3 { found = l.text } else { break }
        }
        let trimmed = found?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? " " : trimmed
    }

    private func openLyrics(find: Bool) {
        withAnimation(.smooth(duration: 0.4)) { lyricsOpen = true }
        if find { lyricsService.findAnywhere(library.trackByID[track.id] ?? track) }
    }

    private func openMenu() { menuOpen = true }

    private func showSaved() {
        savedTask?.cancel()
        savedTask = Task {
            // Another sheet may still be closing (the "…" menu): wait for it, then show the card for a few seconds.
            if menuOpen || queueOpen {
                menuOpen = false
                queueOpen = false
                try? await Task.sleep(for: .milliseconds(500))
            }
            if Task.isCancelled { return }
            savedDetent = .height(230)
            savedOpen = true
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, savedDetent != .large { savedOpen = false }
        }
    }

    private var aboutCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if let url = info?.image {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { ArtworkView(track: track, radius: 0).scaledToFill() }
                            }
                        } else {
                            ArtworkView(track: track, radius: 0).scaledToFill()
                        }
                    }
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text("About the artist").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.6), radius: 4).padding(14)
                    }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.artist).font(.system(size: 17, weight: .bold)).lineLimit(1)
                            Text(libraryLine).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.65))
                        }
                        Spacer(minLength: 8)
                        outlined("View") { router.open(.artist(track.artist)) }
                    }
                    if let bio = info?.bio {
                        Text(bio)
                            .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(bioOpen ? nil : 4)
                            .multilineTextAlignment(.leading)
                            .onTapGesture { withAnimation(.smooth(duration: 0.25)) { bioOpen.toggle() } }
                        Text(bioOpen ? "Show less" : "Show more")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white)
                            .onTapGesture { withAnimation(.smooth(duration: 0.25)) { bioOpen.toggle() } }
                        Text("Source: Wikipedia").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                .padding(14)
            }
        }
    }

    private var libraryLine: String {
        var parts = ["\(songCount) song\(songCount == 1 ? "" : "s")"]
        if plays > 0 { parts.append("\(plays) play\(plays == 1 ? "" : "s")") }
        return parts.joined(separator: " · ") + " in your library"
    }

    private var creditsCard: some View {
        var credits: [(String, String)] = [(track.artist, "Main Artist")]
        if let a = track.albumArtist, !a.isEmpty, a != track.artist { credits.append((a, "Album Artist")) }
        if let c = track.composer, !c.isEmpty {
            for name in c.split(whereSeparator: { ",;/".contains($0) }).map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                credits.append((name, "Composer, Writer"))
            }
        }
        var facts: [(String, String)] = []
        if !track.album.isEmpty { facts.append(("Album", track.album)) }
        if let y = track.year, y > 0 { facts.append(("Released", String(y))) }
        if let g = track.genre, !g.isEmpty { facts.append(("Genre", g)) }
        if let b = track.bpm, b > 0 { facts.append(("Tempo", "\(Int(b.rounded())) BPM")) }
        if let src = track.lyricsSource, !src.isEmpty { facts.append(("Lyrics", src)) }
        let copyright = track.copyright ?? ""
        return card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Credits").font(.system(size: 16, weight: .bold))
                ForEach(Array(credits.enumerated()), id: \.offset) { index, c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.0).font(.system(size: 15, weight: .bold)).lineLimit(1)
                            Text(c.1).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.65))
                        }
                        Spacer(minLength: 8)
                        if index == 0 { outlined("View") { router.open(.artist(c.0)) } }
                    }
                }
                if !facts.isEmpty {
                    Divider().overlay(Color.white.opacity(0.15))
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .firstTextBaseline) {
                            Text(f.0).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65))
                            Spacer(minLength: 12)
                            Text(f.1).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                    }
                }
                if !copyright.isEmpty {
                    Text(copyright).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(14)
        }
    }

    private var exploreCard: some View {
        let mine = library.tracks.filter { $0.artist == track.artist && $0.id != track.id }
        let others = library.tracks.filter { $0.artist != track.artist }
        let a: Track = mine.first ?? track
        let b: Track = others.isEmpty ? track : others[abs(track.artist.hashValue) % others.count]
        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Explore \(track.artist)").font(.system(size: 16, weight: .bold)).lineLimit(1)
                HStack(spacing: 10) {
                    exploreTile("Songs by \(track.artist)", art: a) { router.open(.artist(track.artist)) }
                    exploreTile("Similar to \(track.artist)", art: b) { player.startStation(from: track) }
                    exploreTile("Similar to \(track.title)", art: track) { player.startRadio(from: track) }
                }
            }
            .padding(14)
        }
    }

    private func exploreTile(_ title: String, art: Track, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(0.72, contentMode: .fit)
                .overlay { ArtworkView(track: art, radius: 0).thumbnail(400).scaledToFill() }
                .overlay(alignment: .bottomLeading) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading).lineLimit(3)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(StillButtonStyle())
    }

    // MARK: Lyrics page

    /// The full lyrics page: a solid colour from the cover, big words, a small bar and the play button.
    private var lyricsPage: some View {
        let lines = LyricsParser.parse(track.lyrics ?? "").filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let synced = lines.contains { $0.time != nil }
        var current = -1
        for (i, l) in lines.enumerated() { if let t = l.time, t <= player.position + 0.3 { current = i } }
        let now = current
        return ZStack {
            tint.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 1) {
                        Text(track.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 56)
                    HStack {
                        Button { withAnimation(.smooth(duration: 0.35)) { lyricsOpen = false } } label: {
                            Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40)
                        }
                        .buttonStyle(StillButtonStyle())
                        Spacer()
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16).padding(.top, insets.top + 6)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            if lines.isEmpty {
                                Text(lyricsStatus ?? "No lyrics for this song yet.")
                                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Color.black.opacity(0.55))
                                Button { lyricsService.findAnywhere(library.trackByID[track.id] ?? track) } label: {
                                    Text("Find lyrics").font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                                        .padding(.horizontal, 18).padding(.vertical, 9).background(Capsule().fill(Color.white))
                                }
                                .buttonStyle(StillButtonStyle())
                            }
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                lyricRow(line, index: index, now: now, synced: synced, nextTime: index + 1 < lines.count ? lines[index + 1].time : nil)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 40)
                    }
                    .onChange(of: now) { _, n in
                        guard synced, n >= 0 else { return }
                        withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(n, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                    }
                }

                HStack {
                    ShareLink(item: lyricsShareText(lines), subject: Text(track.title)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 21)).foregroundStyle(Color.white).frame(width: 44, height: 44)
                    }
                    Spacer()
                    Menu { lyricsMenuItems } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.white).frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)

                SPScrubber(showTimes: true).padding(.horizontal, 24).padding(.top, 4)

                Button { player.togglePlay() } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 62, height: 62)
                        SPPlayPause(isPlaying: player.isPlaying, color: tint).frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(StillButtonStyle())
                .transaction { $0.animation = nil }
                .padding(.top, 8).padding(.bottom, max(18, insets.bottom))
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $timingOpen) { LyricsTimingSheet(track: track) }
        .translationTask(translationConfig) { session in
            let items = LyricsParser.parse(track.lyrics ?? "").filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let requests = items.enumerated().map { TranslationSession.Request(sourceText: $0.element.text, clientIdentifier: "\($0.offset)") }
            nonisolated(unsafe) let batch = requests
            nonisolated(unsafe) let translator = session
            guard !batch.isEmpty, let responses = try? await translator.translations(from: batch) else { return }
            var map: [Int: String] = [:]
            for r in responses {
                if let id = r.clientIdentifier.flatMap(Int.init), r.targetText.caseInsensitiveCompare(r.sourceText) != .orderedSame { map[id] = r.targetText }
            }
            withAnimation(.smooth) { translations = map }
        }
        .onChange(of: settings.translationTarget) { _, _ in if settings.translateLyrics { requestTranslation() } }
        .onChange(of: track.id) { _, _ in translations = [:]; if settings.translateLyrics { requestTranslation() } }
    }

    /// What the share button on the lyrics page sends: the words, not the song.
    private func lyricsShareText(_ lines: [LyricLine]) -> String {
        let body = lines.map(\.text).joined(separator: "\n")
        return body.isEmpty ? "\(track.title) – \(track.artist)" : "\(track.title) – \(track.artist)\n\n\(body)"
    }

    private func requestTranslation() {
        let target = Locale.Language(identifier: settings.translationTarget)
        if translationConfig?.target == target { translationConfig?.invalidate() }
        else { translationConfig = TranslationSession.Configuration(source: nil, target: target) }
    }

    /// One lyric line. Tap a line that is not lit yet and the song jumps to it.
    @ViewBuilder private func lyricRow(_ line: LyricLine, index: Int, now: Int, synced: Bool, nextTime: Double?) -> some View {
        let lit = !synced || index <= now
        let isNow = synced && index == now
        let word = settings.wordLyrics && isNow && line.time != nil && nextTime != nil
        let frac: CGFloat = {
            guard word, let t = line.time, let n = nextTime, n > t else { return 1 }
            return CGFloat(min(1, max(0, (player.position - t) / (n - t))))
        }()
        Button {
            if let t = line.time { player.seek(to: t) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.text)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(word ? Color.black.opacity(0.55) : (lit ? Color.white : Color.black.opacity(0.55)))
                    .overlay(alignment: .leading) {
                        if word {
                            Text(line.text).font(.system(size: 23, weight: .bold)).foregroundStyle(Color.white)
                                .mask(alignment: .leading) { Rectangle().scaleEffect(x: frac, anchor: .leading) }
                        }
                    }
                if settings.translateLyrics, let t = translations[index] {
                    Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.white.opacity(lit ? 0.7 : 0.4))
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StillButtonStyle())
        .disabled(line.time == nil)
    }

    /// Lyrics-only "…" menu: the same choices as Apple Music's, with Spotify-style icons.
    @ViewBuilder private var lyricsMenuItems: some View {
        Button {
            settings.translateLyrics.toggle()
            if settings.translateLyrics { requestTranslation() } else { translations = [:] }
        } label: { Label(settings.translateLyrics ? "Translation • On" : "Translation • Off", systemImage: "character.bubble") }
        Picker("Translate to", selection: Binding(get: { settings.translationTarget }, set: { settings.translationTarget = $0 })) {
            ForEach(LyricsLanguages.targets, id: \.0) { Text($0.1).tag($0.0) }
        }
        Button {
            player.lab.vocalCut = player.lab.vocalCut > 0.02 ? 0 : 1
        } label: { Label(player.lab.vocalCut > 0.02 ? "Karaoke • On" : "Karaoke • Off", systemImage: "mic.badge.xmark") }
        Button { settings.wordLyrics.toggle() } label: {
            Label(settings.wordLyrics ? "Line by line" : "Word by word", systemImage: "textformat.abc.dottedunderline")
        }
        Button { timingOpen = true } label: { Label("Adjust timing", systemImage: "gauge.with.dots.needle.33percent") }
        Button { lyricsService.findAnywhere(library.trackByID[track.id] ?? track) } label: { Label("Find other lyrics", systemImage: "text.magnifyingglass") }
        Divider()
        Button { openMenu() } label: { Label("Song options", systemImage: "ellipsis.circle") }
    }

    private func outlined(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(StillButtonStyle())
    }

    // MARK: Queue sheet (a native sheet: glass when half open, solid when pulled up)

    private var queueSheet: some View {
        let upcoming: [QueueItem] = player.upcoming
        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Queue").font(.system(size: 26, weight: .bold)).padding(.horizontal, 22).padding(.top, 28)
                    HStack(spacing: 4) {
                        Text("Playing").foregroundStyle(Color.white.opacity(0.65))
                        Text(player.queueTitle.isEmpty ? track.album : player.queueTitle).fontWeight(.bold).lineLimit(1)
                    }
                    .font(.system(size: 16)).padding(.horizontal, 22).padding(.top, 2)
    
                    queueRow(track, current: true, handle: false)
                        .padding(.horizontal, 22).padding(.top, 14)
    
                    HStack(spacing: 6) {
                        Image(systemName: player.shuffle ? "shuffle" : "text.line.first.and.arrowtriangle.forward")
                        Text(player.shuffle ? "Shuffling from:" : "Next in queue:")
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 6)
    
                    LazyVStack(spacing: 0) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, item in
                            if let t = library.trackByID[item.trackID] {
                                Button { player.jump(toQueueIndex: player.currentIndex + 1 + index) } label: {
                                    queueRow(t, current: false, handle: true)
                                }
                                .buttonStyle(StillButtonStyle())
                                .padding(.horizontal, 22).padding(.vertical, 8)
                            }
                        }
                    }
                    Color.clear.frame(height: 16)
                }
            }
            HStack(spacing: 14) {
                Button { player.setShuffle(!player.shuffle) } label: {
                    queueAction(AnyView(SPGlyph(kind: .shuffle, color: player.shuffle ? accent : Color.white).frame(width: 28, height: 28)), "Shuffle", color: player.shuffle ? accent : Color.white)
                }
                .buttonStyle(StillButtonStyle())
                Menu { SleepTimerMenuItems() } label: { queueAction(AnyView(Image(systemName: "stopwatch").font(.system(size: 25))), "Timer", color: Color.white) }
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.25))
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    private func queueAction(_ icon: AnyView, _ title: String, color: Color) -> some View {
        VStack(spacing: 6) {
            icon.frame(height: 28)
            Text(title).font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity).frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.14)))
    }

    private func queueRow(_ t: Track, current: Bool, handle: Bool) -> some View {
        HStack(spacing: 14) {
            ArtworkView(track: t, radius: 4).thumbnail().frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.title).font(.system(size: 19, weight: .bold)).foregroundStyle(current ? accent : Color.white).lineLimit(1)
                Text(t.artist).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if current {
                Button { player.togglePlay() } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 40, height: 40)
                        SPPlayPause(isPlaying: player.isPlaying, color: Color.black.opacity(0.8)).frame(width: 17, height: 17)
                    }
                }
                .buttonStyle(StillButtonStyle())
            } else if handle {
                Image(systemName: "line.3.horizontal").font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    // MARK: "Saved in" sheet

    private var savedSheet: some View {
        let t = library.trackByID[track.id] ?? track
        let big = savedDetent == .large
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if big {
                    HStack {
                        Button("Cancel") { savedOpen = false }
                        Spacer()
                        Button("Done") { savedOpen = false }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(StillButtonStyle())
                    .padding(.horizontal, 22).padding(.top, 22)
                }
                Text("Saved in").font(.system(size: 20, weight: .bold)).padding(.horizontal, 22).padding(.top, big ? 14 : 28)
                Button {
                    library.toggleFavorite(t)
                    savedTask?.cancel()
                } label: {
                    HStack(spacing: 14) {
                        SPHeartTile(size: 44)
                        Text("Liked Songs").font(.system(size: 16, weight: .bold))
                        Spacer(minLength: 8)
                        if t.isFavorite {
                            ZStack {
                                Circle().fill(accent)
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.black.opacity(0.8))
                            }
                            .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "plus.circle").font(.system(size: 24, weight: .light))
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StillButtonStyle())
                .padding(.top, 8)
                Divider().overlay(Color.white.opacity(0.12)).padding(.horizontal, 22)
                Button {
                    savedOpen = false
                    later { actions.addToPlaylist() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44)
                        Text("New playlist").font(.system(size: 16, weight: .bold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StillButtonStyle())
                Color.clear.frame(height: 120)
            }
        }
        .overlay(alignment: .bottom) {
            if big {
                Button { savedOpen = false } label: {
                    Text("Done").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.black)
                        .frame(width: 128, height: 46).background(Capsule().fill(accent))
                }
                .buttonStyle(StillButtonStyle())
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: "…" menu (native sheet too, so a drag never taps a row)

    private var menuSheet: some View {
        let t = library.trackByID[track.id] ?? track
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ArtworkView(track: track, radius: 4).thumbnail().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(track.artist + " • " + track.album).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 12)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ShareLink(item: ShareItem.text(for: track), subject: Text(track.title)) {
                        menuLabel("Share") { menuGlyph("square.and.arrow.up") }
                    }
                    menuRow("Lyrics • \(lyricLine ? "On" : "Off")", glyph: "captions.bubble", closes: false) {
                        lyricLine.toggle()
                        if lyricLine, t.lyrics == nil { lyricsService.findAnywhere(t) }
                    }
                    menuRow(t.isFavorite ? "Remove from Liked Songs" : "Add to Liked Songs", heart: true) {
                        library.toggleFavorite(t)
                        showSaved()
                    }
                    menuRow("Add to playlist", glyph: "plus.circle") { actions.addToPlaylist() }
                    menuRow("Add to Queue", glyph: "text.line.first.and.arrowtriangle.forward") { player.playAfter([t]) }
                    menuRow("Go to radio", glyph: "dot.radiowaves.left.and.right") {
                        player.startStation(from: t)
                        queueOpen = true
                    }
                    menuRow("Go to album", glyph: "opticaldisc") { router.open(.album("\(t.artist)|\(t.album)")) }
                    menuRow("Go to artist", glyph: "music.mic") { router.open(.artist(t.artist)) }
                    menuRow("View song credits", glyph: "music.note.list") {
                        if lyricsOpen { withAnimation(.smooth(duration: 0.35)) { lyricsOpen = false } }
                        scrollTarget = "credits"
                    }
                    Menu { SleepTimerMenuItems() } label: { menuLabel("Sleep timer") { menuGlyph("timer") } }
                    downloadRow(t)
                    menuRow("Equalizer", glyph: "slider.vertical.3") { actions.equalizer() }
                    menuRow("Edit metadata", glyph: "pencil") { actions.editMetadata() }
                    menuRow("Design cover", glyph: "paintbrush") { actions.designCover() }
                    menuRow("Edit lyrics", glyph: "text.badge.plus") { actions.editLyrics() }
                    menuRow("Customize player", glyph: "slider.horizontal.3") { actions.customize() }
                    Color.clear.frame(height: 60)
                }
            }
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    /// Runs `work` once the sheet that is closing has finished leaving, so the next sheet can open.
    private func later(_ work: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            work()
        }
    }


    private func menuGlyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 21, weight: .regular)).foregroundStyle(Color.white.opacity(0.92))
    }

    private func menuLabel<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 18) {
            icon().frame(width: 28, height: 28)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    private func menuRow(_ title: String, glyph: String = "", heart: Bool = false, closes: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            if closes {
                menuOpen = false
                later(action)
            } else {
                action()
            }
        } label: {
            menuLabel(title) {
                if heart { SPHeartTile(size: 24) } else { menuGlyph(glyph) }
            }
        }
        .buttonStyle(StillButtonStyle())
    }

    /// Download / remove download / progress, for streaming songs only.
    @ViewBuilder private func downloadRow(_ t: Track) -> some View {
        if t.isRemote {
            if t.isDownloaded {
                menuRow("Remove download", glyph: "xmark.circle") { downloads.removeDownloads([t]) }
            } else {
                switch downloads.state(t.id) {
                case .downloading(let p):
                    menuLabel("Downloading… \(Int(p * 100))%") { menuGlyph("arrow.down.circle.dotted") }.opacity(0.6)
                case .queued:
                    menuLabel("Waiting to download…") { menuGlyph("arrow.down.circle.dotted") }.opacity(0.6)
                case .failed:
                    menuRow("Download failed – try again", glyph: "exclamationmark.arrow.circlepath") { downloads.download([t]) }
                case nil:
                    menuRow("Download", glyph: "arrow.down.circle") { downloads.download([t]) }
                }
            }
        }
    }
}

// MARK: - Glyphs

/// The heart on Spotify's purple tile.
private struct SPHeartTile: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#4F2BFF"), Color(hex: "#A6B4FF")], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay { Image(systemName: "heart.fill").font(.system(size: size * 0.42)).foregroundStyle(Color.white) }
    }
}

/// Play and pause drawn by hand, solid, with no cut-outs and no fade.
private struct SPPlayPause: View {
    var isPlaying: Bool
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 24
            if isPlaying {
                for x in [5.5, 14.0] {
                    ctx.fill(Path(CGRect(x: x * k, y: 4 * k, width: 4.5 * k, height: 16 * k)), with: .color(color))
                }
            } else {
                var p = Path()
                p.move(to: CGPoint(x: 6.5 * k, y: 3.5 * k))
                p.addLine(to: CGPoint(x: 20 * k, y: 12 * k))
                p.addLine(to: CGPoint(x: 6.5 * k, y: 20.5 * k))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }
        }
        .transaction { $0.animation = nil }
    }
}

/// Spotify's own line icons, drawn on a 24-point grid.
private struct SPGlyph: View {
    enum Kind { case shuffle, repeatAll, share, queue, timer }
    var kind: Kind
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 24
            let style = StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var p = Path()
            switch kind {
            case .shuffle:
                p.move(to: pt(3, 6.5)); p.addLine(to: pt(6.5, 6.5))
                p.addCurve(to: pt(17.5, 17.5), control1: pt(11, 6.5), control2: pt(13, 17.5))
                p.addLine(to: pt(21, 17.5))
                p.move(to: pt(18.5, 15)); p.addLine(to: pt(21, 17.5)); p.addLine(to: pt(18.5, 20))
                p.move(to: pt(3, 17.5)); p.addLine(to: pt(6.5, 17.5))
                p.addCurve(to: pt(9.6, 16), control1: pt(7.8, 17.5), control2: pt(8.8, 16.9))
                p.move(to: pt(14.4, 8))
                p.addCurve(to: pt(17.5, 6.5), control1: pt(15.2, 7.1), control2: pt(16.2, 6.5))
                p.addLine(to: pt(21, 6.5))
                p.move(to: pt(18.5, 4)); p.addLine(to: pt(21, 6.5)); p.addLine(to: pt(18.5, 9))
            case .repeatAll:
                p.move(to: pt(3.5, 11)); p.addLine(to: pt(3.5, 9.5))
                p.addQuadCurve(to: pt(7, 6), control: pt(3.5, 6))
                p.addLine(to: pt(20.5, 6))
                p.move(to: pt(18, 3.5)); p.addLine(to: pt(20.5, 6)); p.addLine(to: pt(18, 8.5))
                p.move(to: pt(20.5, 13)); p.addLine(to: pt(20.5, 14.5))
                p.addQuadCurve(to: pt(17, 18), control: pt(20.5, 18))
                p.addLine(to: pt(3.5, 18))
                p.move(to: pt(6, 15.5)); p.addLine(to: pt(3.5, 18)); p.addLine(to: pt(6, 20.5))
            case .share:
                p.move(to: pt(8, 10)); p.addLine(to: pt(4.5, 10)); p.addLine(to: pt(4.5, 21)); p.addLine(to: pt(19.5, 21)); p.addLine(to: pt(19.5, 10)); p.addLine(to: pt(16, 10))
                p.move(to: pt(12, 15)); p.addLine(to: pt(12, 3))
                p.move(to: pt(7.5, 7.5)); p.addLine(to: pt(12, 3)); p.addLine(to: pt(16.5, 7.5))
            case .timer:
                p.addEllipse(in: CGRect(x: 4.5 * k, y: 6 * k, width: 15 * k, height: 15 * k))
                p.move(to: pt(12, 6)); p.addLine(to: pt(12, 3))
                p.move(to: pt(9.5, 3)); p.addLine(to: pt(14.5, 3))
                p.move(to: pt(12, 13.5)); p.addLine(to: pt(12, 9.8))
            case .queue:
                p.addRoundedRect(in: CGRect(x: 3 * k, y: 3 * k, width: 18 * k, height: 7 * k), cornerSize: CGSize(width: 3.5 * k, height: 3.5 * k))
                p.move(to: pt(3, 14.5)); p.addLine(to: pt(21, 14.5))
                p.move(to: pt(3, 20)); p.addLine(to: pt(21, 20))
            }
            ctx.stroke(p, with: .color(color), style: style)
        }
    }
}

/// The + that turns into a green check, with a small ring of sparks around it.
private struct SPLikeButton: View {
    var on: Bool
    var accent: Color
    var size: CGFloat
    var action: () -> Void
    /// 0 = at rest, runs to 1 over the burst.
    @State private var burst: CGFloat = 1
    @State private var pop: CGFloat = 1

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(accent.opacity(0.55), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(1 + 0.7 * burst)
                    .opacity(Double(1 - burst) * 0.9)
                confetti
                ZStack {
                    // The ring stays; a green disc grows inside it while the plus turns into a drawn check.
                    Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.6).opacity(on ? 0 : 1)
                    Circle().fill(accent).scaleEffect(on ? 1 : 0.2).opacity(on ? 1 : 0)
                    SPPlus().stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: size * 0.5, height: size * 0.5)
                        .rotationEffect(.degrees(on ? 90 : 0))
                        .scaleEffect(on ? 0.2 : 1)
                        .opacity(on ? 0 : 1)
                    SPCheck().trim(from: 0, to: on ? 1 : 0)
                        .stroke(Color(white: 0.16), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                        .frame(width: size * 0.46, height: size * 0.46)
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.62), value: on)
                .frame(width: size, height: size)
                .scaleEffect(pop)
            }
            .frame(width: size + 16, height: size + 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(StillButtonStyle())
        .onChange(of: on) { _, now in
            guard now else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { burst = 0; pop = 0.55 }
            withAnimation(.easeOut(duration: 0.7)) { burst = 1 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pop = 1 }
        }
    }

    /// About ten tiny green squares leave the circle and fade, staying right beside it.
    private var confetti: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let reach = size * (0.62 + 0.3 * CGFloat(i % 3) * 0.5)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(accent)
                    .frame(width: 3, height: 3)
                    .rotationEffect(.degrees(Double(i) * 47))
                    .offset(y: -(size * 0.5 + (reach - size * 0.5) * burst))
                    .rotationEffect(.degrees(Double(i) * 36))
                    .scaleEffect(1 - 0.4 * burst)
            }
        }
        .frame(width: size, height: size)
        .opacity(Double(max(0, 1 - burst * 1.15)))
        .allowsHitTesting(false)
    }
}

private struct SPPlus: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

private struct SPCheck: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.88))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.95, y: r.minY + r.height * 0.15))
        return p
    }
}

/// Previous / next: a bar and a sharp triangle, solid.
private struct SPSkip: View {
    var forward: Bool
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 24
            var p = Path()
            if forward {
                p.move(to: CGPoint(x: 3.5 * k, y: 4.5 * k)); p.addLine(to: CGPoint(x: 16 * k, y: 12 * k)); p.addLine(to: CGPoint(x: 3.5 * k, y: 19.5 * k)); p.closeSubpath()
                p.addRect(CGRect(x: 17.4 * k, y: 4.5 * k, width: 3.1 * k, height: 15 * k))
            } else {
                p.move(to: CGPoint(x: 20.5 * k, y: 4.5 * k)); p.addLine(to: CGPoint(x: 8 * k, y: 12 * k)); p.addLine(to: CGPoint(x: 20.5 * k, y: 19.5 * k)); p.closeSubpath()
                p.addRect(CGRect(x: 3.5 * k, y: 4.5 * k, width: 3.1 * k, height: 15 * k))
            }
            ctx.fill(p, with: .color(.white))
        }
    }
}

/// Spotify's "devices" glyph: a phone bracket beside a speaker.
private struct ConnectIcon: View {
    var body: some View {
        // The glyph itself, cut out of the reference photo (Assets › ConnectGlyph).
        Image("ConnectGlyph").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).foregroundStyle(Color.white)
    }
}

// MARK: - Scrubber

/// Spotify's thin bar: a white fill and a knob that shows while you hold it. Remaining time sits on the right.
struct SPScrubber: View {
    @Environment(PlayerModel.self) private var player
    var showTimes = true
    @State private var dragging = false
    @State private var dragValue = 0.0

    var body: some View {
        let shown: Double = dragging ? dragValue : player.position
        let total: Double = player.duration
        let progress: Double = total > 0 ? min(1, max(0, shown / total)) : 0
        VStack(spacing: 6) {
            GeometryReader { g in
                let width: CGFloat = max(1, g.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3)).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: width * CGFloat(progress), height: 4)
                    Circle().fill(Color.white).frame(width: 13, height: 13)
                        .offset(x: width * CGFloat(progress) - 6.5)
                        .opacity(dragging ? 1 : 0.0001)
                }
                .frame(height: g.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragging = true
                            dragValue = Double(min(1, max(0, v.location.x / width))) * player.duration
                        }
                        .onEnded { _ in
                            player.seek(to: dragValue)
                            dragging = false
                        }
                )
            }
            .frame(height: 22)
            HStack {
                Text(formatTime(shown))
                Spacer()
                Text("-" + formatTime(max(0, total - shown)))
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.7))
            .opacity(showTimes ? 1 : 0)
        }
    }
}

// MARK: - AirPlay

/// Holds the hidden route picker so our own button can open it.
final class AirPlayTrigger {
    weak var picker: AVRoutePickerView?
    func fire() {
        guard let picker else { return }
        for case let button as UIButton in picker.subviews { button.sendActions(for: .touchUpInside) }
    }
}

struct AirPlayLauncher: UIViewRepresentable {
    let trigger: AirPlayTrigger
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        trigger.picker = v
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { trigger.picker = uiView }
}

// MARK: - Artist info (Wikipedia)

nonisolated struct SPArtistInfo: Sendable {
    var bio: String
    var image: URL?
}

actor SPArtistInfoCache {
    static let shared = SPArtistInfoCache()
    private var store: [String: SPArtistInfo] = [:]
    private var missing: Set<String> = []

    /// "Sematary, Ghost Mountain" and "A feat. B" both look up the first name.
    nonisolated static func mainName(_ artist: String) -> String {
        var name = artist
        for sep in [",", "&", " feat.", " feat ", " ft.", " x ", ";"] {
            if let r = name.range(of: sep, options: .caseInsensitive) { name = String(name[..<r.lowerBound]) }
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    func info(for name: String) async -> SPArtistInfo? {
        if let hit = store[name] { return hit }
        if name.isEmpty || missing.contains(name) { return nil }
        for candidate in [name, name + " (musician)", name + " (band)", name + " (rapper)", name + " (singer)"] {
            if let found = await Self.fetch(candidate) { store[name] = found; return found }
        }
        missing.insert(name)
        return nil
    }

    private static func fetch(_ title: String) async -> SPArtistInfo? {
        let slug = title.replacingOccurrences(of: " ", with: "_")
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&")
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/" + encoded) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Music-iOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if (json["type"] as? String) == "disambiguation" { return nil }
        guard let extract = json["extract"] as? String, !extract.isEmpty else { return nil }
        let text = (extract + " " + (json["description"] as? String ?? "")).lowercased()
        let words = ["singer", "rapper", "band", "musician", "songwriter", "producer", "composer", "vocalist", "duo", "hip hop", "record label", "discography"]
        guard words.contains(where: { text.contains($0) }) else { return nil }
        let thumb = ((json["thumbnail"] as? [String: Any])?["source"] as? String).flatMap { URL(string: $0) }
        return SPArtistInfo(bio: extract, image: thumb)
    }
}


/// Safe-area insets read from the window itself, because a full-screen page that ignores the safe area reads zero from SwiftUI.
enum WindowInsets {
    static var current: EdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        let i = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }
}
