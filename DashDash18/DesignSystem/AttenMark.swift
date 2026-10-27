import SwiftUI

/// Attens merke fra app-ikonet: golfballen med 18 groper i ring (ett per hull) og to skråstreker
/// (DashDash). Geometrien er `docs/design/innlogging/atten-logo.svg`: et utsnitt på 60 av et
/// rutenett på 100, med sentrum i 50,50. Ballen og gropene er like i lys og mørk modus.
struct AttenMark: View {
    /// Ballen (#FFF9DF) og gropene (#E4DBBB), faste i begge moduser.
    private static let ball = Color(red: 255 / 255, green: 249 / 255, blue: 223 / 255)
    private static let dimple = Color(red: 228 / 255, green: 219 / 255, blue: 187 / 255)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 60
            let origin = CGPoint(x: (size.width - 60 * scale) / 2, y: (size.height - 60 * scale) / 2)
            // Fra SVG-rutenettet (utsnittet starter på 20) til punkter i lerretet.
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + (x - 20) * scale, y: origin.y + (y - 20) * scale)
            }
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius * scale, y: center.y - radius * scale,
                                       width: 2 * radius * scale, height: 2 * radius * scale))
            }
            context.fill(circle(p(50, 50), 29.3), with: .color(Self.ball))
            for hole in 0..<18 {
                // Første grop rett opp, så hver 20° med klokka.
                let angle = Double(hole) * 20 * .pi / 180
                context.fill(circle(p(50 + 21.5 * sin(angle), 50 - 21.5 * cos(angle)), 1.95),
                             with: .color(Self.dimple))
            }
            var dashes = Path()
            dashes.move(to: p(47.1, 40.6))
            dashes.addLine(to: p(42.2, 58.6))
            dashes.move(to: p(56.9, 40.6))
            dashes.addLine(to: p(52.0, 58.6))
            context.stroke(dashes, with: .color(.ddRust),
                           style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach([Color.ddForestDeep, Color.ddBackground], id: \.self) { background in
            HStack(spacing: 24) {
                AttenMark().frame(width: 112, height: 112)
                AttenMark().frame(width: 36, height: 36)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(background)
        }
    }
}
