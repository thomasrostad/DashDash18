import SwiftUI

/// Feiringen etter et hull: birdie, eagle, albatross eller hole in one. Står i
/// `level.duration`, eller til den trykkes bort. Med Reduce Motion: ingen konfetti.
struct FeiringOverlay: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Skoggrønn grunn med lys bak tittelen, som `.gg-celebrate`.
            Rectangle()
                .fill(celebration.level == .ace ? Color(uiColor: DDRGBA(0x0B1F18).uiColor) : Color.ddForestDeep)
                .opacity(0.96)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(celebration.level == .birdie ? 0.14 : 0.24), .clear],
                           center: .center, startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if !reduceMotion && celebration.level.particles > 0 {
                ConfettiView(level: celebration.level)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
                Text(celebration.eyebrow)
                    .ddEyebrow(color: accent.opacity(0.75))
                Text(celebration.level.title)
                    .font(.dd(.sans, size: celebration.level == .birdie ? 44 : 54, weight: .light, relativeTo: .largeTitle))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
                Text(celebration.text)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddOnDark.opacity(0.85))
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let match = celebration.matchText { pill(match) }
                    if let points = celebration.points { pill("+\(points) poeng") }
                    if let place = celebration.place { pill("\(place). plass") }
                }
                Button(celebration.nextHole.map { "Videre til hull \($0)" } ?? "Videre", action: onDismiss)
                    .buttonStyle(.dd(.primary))
                    .padding(.top, 12)
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

    /// Gull for eagle og bedre, lys grønn for birdie (PWA-ens `niv-birdie`).
    private var accent: Color {
        celebration.level == .birdie ? .ddLimeBackground : .ddGold
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.dd(.sans, size: 14, weight: .semibold, relativeTo: .subheadline))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(Color.ddOnDark)
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

    private static let colors: [Color] = [.ddGold, .ddLime, .ddRust, .ddOnDark, .ddYellow]

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
                      height: Double.random(in: 8...15), color: Self.colors.randomElement() ?? .ddGold)
            }
        }
    }
}
