import SwiftUI

/// Feiringen etter et hull: birdie, eagle, albatross eller hole in one. Står i
/// `level.duration`, eller til den trykkes bort. Med Reduce Motion: ingen konfetti.
struct FeiringOverlay: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
            if !reduceMotion && celebration.level.particles > 0 {
                ConfettiView(level: celebration.level)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
                Text(celebration.eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(celebration.level.title)
                    .font(.system(size: celebration.level == .ace ? 46 : 40, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(celebration.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let match = celebration.matchText { pill(match) }
                    if let points = celebration.points { pill("+\(points) poeng") }
                    if let place = celebration.place { pill("\(place). plass") }
                }
                Button(celebration.nextHole.map { "Videre til hull \($0)" } ?? "Videre", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.top, 8)
            }
            .padding(28)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: celebration.id) {
            try? await Task.sleep(for: celebration.level.duration)
            if !Task.isCancelled { onDismiss() }
        }
        .sensoryFeedback(.success, trigger: celebration.id)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2), in: .capsule)
            .foregroundStyle(.white)
    }
}

/// Konfetti som skytes opp fra bunnen og faller (`startKonfetti`). Tegnes i én Canvas.
private struct ConfettiView: View {
    let level: CelebrationLevel
    @State private var start = Date()
    @State private var pieces: [Piece] = []

    struct Piece {
        var x: Double, vx: Double, vy: Double, rotation: Double, spin: Double
        var width: Double, height: Double, color: Color
    }

    private static let colors: [Color] = [.yellow, .green, .orange, .white, .mint]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start) * 60   // i «rammer», som PWA-en
                let total = Double(level.duration.components.seconds) * 60
                    + Double(level.duration.components.attoseconds) / 1e18 * 60
                let fade = max(0, min(1, (total - t) / 42))
                for p in pieces {
                    // Posisjon etter t rammer med tyngde 0,19 og luftmotstand 0,995 i x.
                    let x = p.x * size.width + p.vx * (1 - pow(0.995, t)) / 0.005
                    let y = size.height + 12 + p.vy * t + 0.19 * t * t / 2
                    guard y < size.height + 40 else { continue }
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.rotation + p.spin * t))
                    c.fill(Path(CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)),
                           with: .color(p.color))
                }
            }
        }
        .onAppear {
            start = Date()
            pieces = (0..<level.particles).map { _ in
                Piece(x: 0.5 + Double.random(in: -0.35...0.35), vx: Double.random(in: -1.7...1.7),
                      vy: -Double.random(in: 10...17), rotation: Double.random(in: 0...Double.pi),
                      spin: Double.random(in: -0.17...0.17), width: Double.random(in: 5...10),
                      height: Double.random(in: 8...15), color: Self.colors.randomElement() ?? .yellow)
            }
        }
    }
}
