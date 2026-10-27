import SwiftUI

struct SearchLayer: View {
    @Environment(Router.self) private var router
    @Environment(PlayerModel.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Bool
    @State private var watching = true

    static let size: CGFloat = 62
    static let gap: CGFloat = 8
    static let minSize: CGFloat = 49
    static let minMargin: CGFloat = 27
    static let barWidth: CGFloat = 188

    @State private var barMinimized = false
    @State private var addVisible = true
    @State private var settleToken = 0
    @State private var barFrame: CGRect?
    @State private var lastReading: CGRect?

    private var collapsed: Bool { barMinimized && !router.searchActive }

    private func barChanged(_ minimized: Bool) {
        settleToken += 1
        let token = settleToken
        if minimized {
            withAnimation(.easeOut(duration: 0.12)) { addVisible = false }
            withAnimation(.snappy(duration: 0.34)) { barMinimized = true }
        } else {
            withAnimation(.snappy(duration: 0.34)) { barMinimized = false }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                if token == settleToken { withAnimation(.snappy(duration: 0.24)) { addVisible = true } }
            }
        }
    }

    var body: some View {
        @Bindable var router = router
        GeometryReader { geo in
            let W = geo.size.width
            let barInset = max(geo.safeAreaInsets.bottom - 12, 8)
            let searching = router.searchActive
            let sz = collapsed ? Self.minSize : Self.size

            let origin = geo.frame(in: .global).minX
            let barMinX = barFrame.map { $0.minX - origin } ?? (W - Self.barWidth) / 2
            let barMaxX = barFrame.map { $0.maxX - origin } ?? (W + Self.barWidth) / 2
            let left = max(8, barMinX - Self.gap - Self.size)
            let addX: CGFloat = searching ? 16 : collapsed ? Self.minMargin + Self.minSize + 11 : left
            let pillX: CGFloat = searching ? 16 + Self.size + Self.gap
                : collapsed ? W - Self.minMargin - Self.minSize
                : min(W - 8 - Self.size, barMaxX + Self.gap)
            let pillW: CGFloat = searching ? W - 32 - Self.size - Self.gap : sz
            let pillH: CGFloat = searching ? Self.size : sz
            let bottom: CGFloat = searching ? 8 : barInset + (Self.size - sz) / 2

            ZStack(alignment: .bottomLeading) {
                if searching {
                    NavigationStack {
                        SearchView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                    .background(Color(.systemBackground))
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // FIXED: Ensure taps are absorbed cleanly
                    .contentShape(Rectangle())
                    .onTapGesture { focused = false } 
                }

                if !searching, player.current != nil {
                    MiniPlayerCapsule()
                        .padding(.horizontal, 16)
                        .padding(.bottom, barInset + Self.size + 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ZStack(alignment: .bottomLeading) {
                    if !searching && !collapsed && addVisible {
                        AddMusicMenu(size: Self.size)
                            .frame(width: Self.size, height: Self.size)
                            .offset(x: addX)
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }

                    GlassEffectContainer(spacing: 10) {
                        ZStack(alignment: .bottomLeading) {
                            if searching {
                                Button {
                                    router.closeSearch()
                                } label: {
                                    Image(systemName: "chevron.backward")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: Self.size, height: Self.size)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: Circle())
                                .frame(width: Self.size, height: Self.size)
                                .offset(x: addX)
                                .transition(.opacity)
                            }

                            searchPill(searching: searching, width: pillW, height: pillH)
                                .offset(x: pillX)
                        }
                    }
                }
                .padding(.bottom, bottom)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .ignoresSafeArea(.container, edges: searching ? [] : .bottom)
            .animation(.smooth(duration: 0.42), value: searching)
            .animation(.smooth, value: player.current == nil)
        }
        .onChange(of: router.searchActive) { _, on in
            guard on else { focused = false; return }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                if router.searchActive { focused = true }
            }
        }
        .onChange(of: scenePhase == .active && !router.showPlayer && !router.showFullLyrics, initial: true) { _, on in watching = on }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(watching ? 40 : 1000))
                guard watching else { continue }
                let sys = TabBarProbe.isMinimized() ?? router.collapsed
                if sys != barMinimized { barChanged(sys) }
                let reading = TabBarProbe.expandedFrame()
                if let r = reading, let last = lastReading, r.isApproximately(last),
                   !(barFrame.map { $0.isApproximately(r) } ?? false) {
                    barFrame = r
                }
                lastReading = reading
            }
        }
    }

    private func searchPill(searching: Bool, width: CGFloat, height: CGFloat) -> some View {
        @Bindable var router = router
        return ZStack {
            if searching {
                HStack(spacing: 8) {
                    // Spotify style search icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                    TextField("Songs, Artists, Albums", text: $router.searchText)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { focused = false }
                    if !router.searchText.isEmpty {
                        Button { router.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if focused {
                        Button { focused = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide Keyboard")
                    }
                }
                .padding(.horizontal, 18)
                .frame(width: width, height: height)
                .transition(.opacity)
            } else {
                Button {
                    router.searchActive = true
                } label: {
                    // Spotify style search icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: width, height: height)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private extension CGRect {
    func isApproximately(_ o: CGRect) -> Bool {
        abs(minX - o.minX) < 0.5 && abs(maxX - o.maxX) < 0.5 && abs(minY - o.minY) < 0.5 && abs(maxY - o.maxY) < 0.5
    }
}
