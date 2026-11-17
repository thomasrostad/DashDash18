import SwiftUI

/// Feiringen etter et hull: birdie, eagle, albatross eller hole in one. Står i
/// `level.duration`, eller til den trykkes bort. Med Reduce Motion: ingen konfetti. Med VoiceOver
/// lukkes den ikke av seg selv, så den rekker å bli lest opp; «Videre» lukker.
///
/// Innslaget går i takt: tittelen spretter inn, ringer og gnister går ut fra den, så kommer
/// resten etter hverandre. Eagle og bedre får konfetti fra hjørnene og en glans over gullet.
struct FeiringOverlay: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// Settes når overlayet vises. Hver del har sin egen forsinkelse, så de kommer etter hverandre.
    @State private var shown = false
    /// Glansen over gulltittelen (eagle og bedre).
    @State private var shine = false

    var body: some View {
        ZStack {
            // Skoggrønn grunn med lys bak tittelen, som `.gg-celebrate`.
            Rectangle()
                .fill(celebration.level == .ace ? Color.ddCelebrateAce : Color.ddForestDeep)
                .opacity(0.96)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(celebration.level == .birdie ? 0.16 : 0.26), .clear],
                           center: .center, startRadius: 0, endRadius: 340)
                .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.7), value: shown)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if !reduceMotion {
                FeiringEffects(level: celebration.level, accent: accent)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
                Text(celebration.eyebrow)
                    .ddEyebrow(color: accent.opacity(0.75))
                    .modifier(Entrance(shown: shown, delay: 0.2))
                title
                    .overlay { shineOverlay }
                    .scaleEffect(shown || reduceMotion ? 1 : 0.5)
                    .blur(radius: shown || reduceMotion ? 0 : 12)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.45).delay(0.04),
                               value: shown)
                Text(celebration.text)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddHeroSecondary)
                    .multilineTextAlignment(.center)
                    .modifier(Entrance(shown: shown, delay: 0.32))
                HStack(spacing: 8) {
                    if let match = celebration.matchText { pill(match) }
                    if let points = celebration.points { pill("+\(points) poeng") }
                    if let place = celebration.place { pill("\(place). plass") }
                }
                .modifier(Entrance(shown: shown, delay: 0.42))
                Button(celebration.nextHole.map { "Videre til hull \($0)" } ?? "Videre", action: onDismiss)
                    .buttonStyle(.dd(.primary))
                    .padding(.top, 12)
                    .modifier(Entrance(shown: shown, delay: 0.52))
            }
            .padding(28)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            shown = true
            if celebration.level >= .eagle && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).delay(0.5)) { shine = true }
            }
        }
        .task(id: celebration.id) {
            guard !voiceOver else { return }
            try? await Task.sleep(for: celebration.level.duration)
            if !Task.isCancelled { onDismiss() }
        }
        .sensoryFeedback(.success, trigger: celebration.id)
    }

    /// Gull for eagle og bedre, lys grønn for birdie (PWA-ens `niv-birdie`).
    private var accent: Color {
        celebration.level == .birdie ? .ddLimeBackground : .ddGold
    }

    private var title: some View {
        Text(celebration.level.title)
            .font(.dd(.sans, size: celebration.level == .birdie ? 44 : 54, weight: .light, relativeTo: .largeTitle))
            .foregroundStyle(accent)
            .multilineTextAlignment(.center)
    }

    /// En lysstripe som glir én gang over gulltittelen.
    @ViewBuilder
    private var shineOverlay: some View {
        if celebration.level >= .eagle && !reduceMotion {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: shine ? geo.size.width * 1.1 : -geo.size.width * 0.5)
            }
            .mask(title)
            .allowsHitTesting(false)
        }
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

/// Toner inn og løfter seg litt, etter `delay`. Med Reduce Motion: bare toning.
private struct Entrance: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2).delay(delay),
                       value: shown)
    }
}

/// Ringer og gnister fra tittelen, og konfetti fra hjørnene nede (eagle og bedre). Alt tegnes i én
/// Canvas med tid i sekunder. Konfettien har luftmotstand, så den daler, og den vender seg som papir.
private struct FeiringEffects: View {
    let level: CelebrationLevel
    let accent: Color
    @State private var start = Date()
    @State private var sparks: [Spark]
    @State private var pieces: [Piece]

    /// Partiklene lages her, ikke i `onAppear`: der kom de ikke med i tegningen.
    init(level: CelebrationLevel, accent: Color) {
        self.level = level
        self.accent = accent
        _sparks = State(initialValue: Self.makeSparks(level: level, accent: accent))
        _pieces = State(initialValue: Self.makePieces(level: level))
    }

    /// Gnist fra tittelen: fart ut i en retning, bremses fort.
    struct Spark {
        var angle: Double, speed: Double, life: Double, radius: Double, color: Color
    }

    enum Shape { case rect, circle, streamer }

    /// Konfettibit. Farten er i punkter per sekund på en skjerm som er 874 punkter høy.
    struct Piece {
        var fromLeft: Bool, fireAt: Double
        var vx: Double, vy: Double, drag: Double
        var rotation: Double, spin: Double, flip: Double, flipSpeed: Double
        var wobble: Double, wobbleSpeed: Double
        var width: Double, height: Double, shape: Shape, color: Color
    }

    private static let colors: [Color] = [.ddGold, .ddLime, .ddRust, .ddOnDark, .ddYellow]
    private static let gravity = 900.0

    /// Tittelen står litt over midten av skjermen.
    private func center(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height / 2 - 44) }

    private var total: Double {
        Double(level.duration.components.seconds) + Double(level.duration.components.attoseconds) / 1e18
    }

    private var ringCount: Int { level >= .albatross ? 3 : 2 }

    /// Salvene med konfetti: én for eagle og albatross, tre for hole in one.
    private static func volleys(_ level: CelebrationLevel) -> [Double] {
        switch level {
        case .birdie: []
        case .eagle, .albatross: [0.12]
        case .ace: [0.12, 1.6, 3.0]
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                // Alt toner ut det siste halve sekundet før feiringen lukkes.
                let endFade = max(0, min(1, (total - t) / 0.5))
                drawRings(ctx, size: size, t: t)
                drawSparks(ctx, size: size, t: t)
                var c = ctx
                c.opacity = endFade
                drawConfetti(c, size: size, t: t)
            }
        }
        .onAppear { start = Date() }
    }

    private func drawRings(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let c = center(size)
        let maxRadius = max(size.width, size.height) * 0.6
        for i in 0..<ringCount {
            let p = (t - 0.08 - Double(i) * 0.2) / 1.3
            guard p > 0, p < 1 else { continue }
            let eased = 1 - pow(1 - p, 3)
            let r = 50 + eased * maxRadius
            var g = ctx
            g.opacity = (1 - p) * 0.5
            g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(accent), lineWidth: 1 + 2.5 * (1 - p))
        }
    }

    private func drawSparks(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let c = center(size)
        let k = 4.5
        let t0 = t - 0.1
        guard t0 > 0 else { return }
        for s in sparks where t0 < s.life {
            let p = t0 / s.life
            let travel = s.speed / k * (1 - exp(-k * t0))
            let x = c.x + cos(s.angle) * travel
            let y = c.y + sin(s.angle) * travel + 120 * t0 * t0
            let r = s.radius * (1 - p * 0.6)
            var g = ctx
            g.opacity = pow(1 - p, 1.5)
            g.fill(Path(ellipseIn: CGRect(x: x - r * 2.5, y: y - r * 2.5, width: r * 5, height: r * 5)),
                   with: .color(s.color.opacity(0.25)))
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(s.color))
        }
    }

    private func drawConfetti(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let scale = size.height / 874
        let g = Self.gravity * scale
        for p in pieces {
            let tp = t - p.fireAt
            guard tp > 0 else { continue }
            // Tyngde og luftmotstand: v' = g − k·v. Løst for posisjonen.
            let k = p.drag
            let decay = 1 - exp(-k * tp)
            let vx = p.vx * scale * (p.fromLeft ? 1 : -1)
            let vy = -p.vy * scale
            let wobble = sin(p.wobbleSpeed * tp + p.rotation) * p.wobble * min(1, tp * 1.2)
            let x = (p.fromLeft ? -8 : size.width + 8) + vx / k * decay + wobble
            let y = size.height + 8 + (g / k) * tp + (vy - g / k) / k * decay
            guard y < size.height + 40, x > -60, x < size.width + 60 else { continue }
            // Papiret vender seg: bredden følger cos, og baksiden er litt mørkere.
            let flip = cos(p.flip + p.flipSpeed * tp)
            var c = ctx
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(p.rotation + p.spin * tp))
            c.scaleBy(x: max(0.12, abs(flip)), y: 1)
            if flip < 0 { c.opacity *= 0.75 }
            let rect = CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)
            switch p.shape {
            case .rect: c.fill(Path(rect), with: .color(p.color))
            case .circle: c.fill(Path(ellipseIn: rect), with: .color(p.color))
            case .streamer: c.fill(Path(roundedRect: rect, cornerRadius: p.width / 2), with: .color(p.color))
            }
        }
    }

    private static func makeSparks(level: CelebrationLevel, accent: Color) -> [Spark] {
        let colors: [Color] = level == .birdie ? [.ddLimeBackground, .ddOnDark, .ddLime] : [.ddGold, .ddOnDark, .ddYellow]
        let count = level == .birdie ? 18 : 26
        return (0..<count).map { i in
            Spark(angle: Double(i) / Double(count) * 2 * .pi + Double.random(in: -0.15...0.15),
                  speed: Double.random(in: 280...620), life: Double.random(in: 0.7...1.1),
                  radius: Double.random(in: 1.6...3.4), color: colors.randomElement() ?? accent)
        }
    }

    private static func makePieces(level: CelebrationLevel) -> [Piece] {
        let times = volleys(level)
        guard !times.isEmpty else { return [] }
        // Første salve er størst; på hole in one deles resten på de to neste.
        let first = times.count == 1 ? level.particles : level.particles * 45 / 100
        let rest = times.count > 1 ? (level.particles - first) / (times.count - 1) : 0
        return times.enumerated().flatMap { index, fireAt in
            (0..<(index == 0 ? first : rest)).map { i in makePiece(fromLeft: i.isMultiple(of: 2), fireAt: fireAt) }
        }
    }

    private static func makePiece(fromLeft: Bool, fireAt: Double) -> Piece {
        let up = Double.random(in: 1500...2500)
        let shape: Shape = [.rect, .rect, .rect, .circle, .streamer].randomElement() ?? .rect
        let (w, h): (Double, Double) = switch shape {
        case .rect: (Double.random(in: 6...10), Double.random(in: 9...14))
        case .circle: (Double.random(in: 5...8), 0)
        case .streamer: (Double.random(in: 3...4), Double.random(in: 16...24))
        }
        return Piece(fromLeft: fromLeft, fireAt: fireAt + Double.random(in: 0...0.08),
                     vx: up * Double.random(in: 0.1...0.42), vy: up,
                     drag: shape == .streamer ? Double.random(in: 2.8...3.4) : Double.random(in: 2.4...3.1),
                     rotation: Double.random(in: 0...(2 * .pi)), spin: Double.random(in: -4...4),
                     flip: Double.random(in: 0...(2 * .pi)), flipSpeed: Double.random(in: 6...13),
                     wobble: Double.random(in: 10...28), wobbleSpeed: Double.random(in: 2.5...5),
                     width: w, height: shape == .circle ? w : h, shape: shape,
                     color: colors.randomElement() ?? .ddGold)
    }
}
