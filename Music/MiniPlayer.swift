import SwiftUI

struct MiniPlayer: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var roomy = true

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let t = player.current {
                    ArtworkView(track: t, radius: 7).thumbnail()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "music.note").foregroundStyle(.secondary).frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.current?.title ?? "No Music Playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(player.current?.artist ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(player.current == nil ? 0 : 0.62))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if player.current != nil { router.showPlayer = true } }

            Button { player.togglePlay() } label: {
                PlayPauseIcon(isPlaying: player.isPlaying, size: 22, color: Color.primary)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TransportPressStyle(scales: false, highlight: false))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            
            if roomy {
                FavoriteStarButton(isFavorite: player.current?.isFavorite ?? false, size: 22, filled: false) {
                    if let t = player.current { player.library.toggleFavorite(t) }
                }
                
                AirPlayButton()
                    .frame(width: 22, height: 22)
                
                SkipButton(direction: .next, size: 22, frame: 42, color: Color.primary, highlight: false) { player.next() }
            }
        }
        .foregroundStyle(player.current == nil ? Color.primary.opacity(0.5) : Color.primary)
        .disabled(player.current == nil)
        .padding(.horizontal, 16)
        .miniPlayerSwipes()
        .onAppear { roomy = placement != .inline }
        .onChange(of: placement) { _, new in if !router.showPlayer { roomy = new != .inline } }
        .onChange(of: router.showPlayer) { _, open in if !open { roomy = placement != .inline } }
    }
}

struct MiniPlayerCapsule: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    private var style: AppTheme.MiniPlayer { ThemeStore.shared.current.miniPlayer }

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ArtworkView(track: track, radius: 9).thumbnail()
                        .frame(width: 38, height: 38)
                        .id(track.id)
                        // CLEAN SLIDE, NO FADE
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if style != .compact {
                            Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .id(track.id)
                    // CLEAN SLIDE, NO FADE
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { router.showPlayer = true }

                Button { player.togglePlay() } label: {
                    PlayPauseIcon(isPlaying: player.isPlaying, size: 22, color: Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background {
                            if player.isBuffering {
                                ProgressView().controlSize(.small)
                            } else if style != .bar {
                                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                                MiniPlayerProgress(ring: true)
                            }
                        }
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                
                FavoriteStarButton(isFavorite: track.isFavorite, size: 22, filled: false) {
                    player.library.toggleFavorite(track)
                }
                
                AirPlayButton()
                    .frame(width: 22, height: 22)
                
                SkipButton(direction: .next, size: 22, frame: 44, color: Color.primary, highlight: false) { player.next() }
            }
            .buttonStyle(.plain)
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(height: style == .compact ? 52 : 62)
            .overlay(alignment: .bottom) {
                if style == .bar {
                    MiniPlayerProgress(ring: false)
                        .frame(height: 3)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 4)
                }
            }
            .glassEffect(ThemeStore.shared.glass.interactive(), in: Capsule())
            .contentShape(Capsule())
            .miniPlayerSwipes()
            // REMOVED .animation(.smooth, value: track.id)
        }
    }
}

private struct MiniPlayerProgress: View {
    @Environment(PlayerModel.self) private var player
    let ring: Bool

    var body: some View {
        let fraction = player.duration > 0 ? player.position / player.duration : 0
        if ring {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        } else {
            GeometryReader { g in
                Capsule().fill(Theme.accent).frame(width: max(0, g.size.width * fraction), height: 3)
            }
        }
    }
}

// MARK: - Swipes
struct MiniPlayerSwipes: ViewModifier {
    @Environment(PlayerModel.self) private var player
    @State private var drag: CGSize = .zero
    @State private var leaving = false
    @State private var skips = 0
    @State private var stops = 0

    private static let skipDistance: CGFloat = 60
    private static let stopDistance: CGFloat = 45

    func body(content: Content) -> some View {
        content
            .offset(x: leaving ? 0 : rubber(drag.width, limit: 70), y: leaving ? 140 : max(0, rubber(drag.height, limit: 60)))
            .opacity(leaving ? 0 : 1 - min(0.5, max(0, drag.height) / 160))
            .scaleEffect(leaving ? 0.9 : 1)
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { v in
                        guard player.current != nil else { return }
                        drag = abs(v.translation.width) > abs(v.translation.height)
                            ? CGSize(width: v.translation.width, height: 0)
                            : CGSize(width: 0, height: max(0, v.translation.height))
                    }
                    .onEnded { v in
                        let dx = v.predictedEndTranslation.width, dy = v.predictedEndTranslation.height
                        if drag.width != 0, abs(dx) > Self.skipDistance {
                            skips += 1
                            if dx < 0 { player.next() } else { player.previous(always: true) }
                        } else if drag.height > 0, dy > Self.stopDistance {
                            stops += 1
                            withAnimation(.easeIn(duration: 0.22)) { leaving = true }
                            Task {
                                try? await Task.sleep(for: .milliseconds(220))
                                player.stop()
                                leaving = false
                                drag = .zero
                            }
                            return
                        }
                        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { drag = .zero }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: skips)
            .sensoryFeedback(.impact(weight: .medium), trigger: stops)
    }

    private func rubber(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        let s: CGFloat = x < 0 ? -1 : 1
        return s * limit * (1 - 1 / (abs(x) / limit + 1))
    }
}

extension View { func miniPlayerSwipes() -> some View { modifier(MiniPlayerSwipes()) } }
