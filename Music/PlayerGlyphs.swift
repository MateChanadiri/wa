import SwiftUI
import AVKit

// MARK: - Press style
struct TransportPressStyle: ButtonStyle {
    var scales: Bool = false
    var highlight: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        return configuration.label
            .background {
                if highlight {
                    Circle()
                        .fill(Color.white.opacity(pressed ? 0.2 : 0))
                        .animation(.easeOut(duration: pressed ? 0.08 : 0.35), value: pressed)
                }
            }
            .scaleEffect(scales && pressed ? 0.92 : 1)
            .animation(.spring(duration: 0.28, bounce: 0.2), value: pressed)
    }
}

// MARK: - Skip glyph
struct SkipGlyph: View, Animatable {
    var phase: CGFloat
    var size: CGFloat
    var mirrored: Bool
    var color: Color
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    private func slot(_ k: Int) -> CGFloat {
        let raw: CGFloat = (CGFloat(k) + phase).truncatingRemainder(dividingBy: 3)
        return raw - 1
    }

    private func beltScale(_ s: CGFloat) -> CGFloat {
        if s < 0 { return max(0, 1 + 1.3 * s) }
        if s > 1 { return max(0, 1 - 1.8 * (s - 1)) }
        return 1
    }

    private func beltOpacity(_ s: CGFloat) -> CGFloat {
        if s < 0 { return min(1, max(0, 1 + 0.5 * s)) }
        if s > 1 { return max(0, 1 - 1.3 * (s - 1)) }
        return 1
    }

    var body: some View {
        let w: CGFloat = size * 0.86
        let pitch: CGFloat = w * 0.84
        let total: CGFloat = pitch + w
        ZStack(alignment: .leading) {
            ForEach(0..<3, id: \.self) { (k: Int) in
                let s: CGFloat = slot(k)
                triangle(w: w)
                    .scaleEffect(beltScale(s))
                    .opacity(Double(beltOpacity(s)))
                    .offset(x: s * pitch)
            }
        }
        .frame(width: total, height: size, alignment: .leading)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }

    private func triangle(w: CGFloat) -> some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.92, weight: .regular))
            .foregroundStyle(color)
            .frame(width: w, height: size)
    }
}

struct SkipButton: View {
    enum Direction { case previous, next }

    let direction: Direction
    var size: CGFloat = 32
    var frame: CGFloat = 76
    var color: Color = .white
    var highlight: Bool = true
    let action: () -> Void

    @State private var phase: CGFloat = 0

    var body: some View {
        Button {
            action()
            withAnimation(.timingCurve(0.25, 0.9, 0.3, 1, duration: 0.44)) { phase += 1 }
        } label: {
            SkipGlyph(phase: phase, size: size, mirrored: direction == .previous, color: color)
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(TransportPressStyle(scales: false, highlight: highlight))
        .accessibilityLabel(direction == .next ? "Next" : "Previous")
    }
}

// MARK: - Play / pause icon
// NO ANIMATION. Snaps instantly.
struct PlayPauseIcon: View {
    let isPlaying: Bool
    var size: CGFloat = 46
    var color: Color = .white

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

// MARK: - Favourite star (with Confetti)
struct FavoriteStarButton: View {
    let isFavorite: Bool
    var size: CGFloat = 36
    var filled: Bool = true
    let action: () -> Void

    @State private var confettiTrigger = 0

    var body: some View {
        Button {
            if !isFavorite { confettiTrigger += 1 }
            action()
        } label: {
            ZStack {
                if filled { Circle().fill(Color.white.opacity(0.18)) }
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .overlay {
                ConfettiBurst(trigger: confettiTrigger)
            }
        }
        .buttonStyle(TransportPressStyle(scales: false, highlight: false))
        .sensoryFeedback(.impact(weight: .light), trigger: confettiTrigger)
        .accessibilityLabel("Favorite")
        .accessibilityValue(isFavorite ? "On" : "Off")
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}

// MARK: - Confetti Burst
struct ConfettiBurst: View {
    let trigger: Int
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scale: CGFloat = 1
        var rotation: Double = 0
        var color: Color
        var opacity: Double = 1
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Rectangle()
                    .fill(p.color)
                    .frame(width: 5, height: 5)
                    .scaleEffect(p.scale)
                    .rotationEffect(.degrees(p.rotation))
                    .offset(x: p.x, y: p.y)
                    .opacity(p.opacity)
            }
        }
        .onChange(of: trigger) { _, newValue in
            if newValue > 0 { spawn() }
        }
    }

    private func spawn() {
        particles.removeAll()
        let colors: [Color] = [.green, .blue, .yellow, .pink, .purple, .orange]
        for _ in 0..<20 {
            let angle = Double.random(in: 0...2 * .pi)
            let distance = CGFloat.random(in: 20...70)
            let p = Particle(
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                scale: CGFloat.random(in: 0.5...1.2),
                rotation: Double.random(in: 0...360),
                color: colors.randomElement() ?? .green
            )
            particles.append(p)
        }

        withAnimation(.easeOut(duration: 0.7)) {
            for i in particles.indices {
                particles[i].x *= 1.8
                particles[i].y *= 1.8
                particles[i].scale = 0
                particles[i].opacity = 0
            }
        }
    }
}

// MARK: - AirPlay Button
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemGreen
        picker.prioritizesVideoDevices = false
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Swipe Down to Minimize Modifier
// Attach this to your NowPlayingView root ZStack
public struct SwipeDownToDismiss: ViewModifier {
    @Binding var isPresented: Bool
    @State private var offset: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 250 {
                            withAnimation(.easeOut(duration: 0.2)) { offset = 1000 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                isPresented = false
                                offset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                            }
                        }
                    }
            )
    }
}

extension View {
    public func swipeDownToDismiss(isPresented: Binding<Bool>) -> some View {
        self.modifier(SwipeDownToDismiss(isPresented: isPresented))
    }
}
