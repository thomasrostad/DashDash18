import GolfgutuCore
import SwiftUI
import Testing
import UIKit
@testable import DashDash18

/// Rendringsmatrisen fra utbedringsplanen (0.3): lys og mørk × Dynamic Type L, xxxL og AX3 ×
/// 375, 402 og 440 pt. Uten et bibliotek for bildesammenligning sjekker vi at komponentene tegnes,
/// holder seg innenfor bredden og vokser med teksten. Skjermbildene i lys og mørk tas med
/// skjermprøvene (`-DDDesignScreen`), se `docs/ui-utbedring.md`.
@MainActor
struct RenderMatrixTests {
    static let widths: [CGFloat] = [375, 402, 440]
    static let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3]
    static let schemes: [ColorScheme] = [.light, .dark]

    private func render(_ view: some View, width: CGFloat, size: DynamicTypeSize, scheme: ColorScheme) -> CGSize? {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "nb_NO")))
        renderer.scale = 1
        return renderer.uiImage?.size
    }

    @Test("Hullkortet tegnes i hele matrisen og blir høyere med større tekst")
    func hullkort() throws {
        let card = HullkortView(card: DesignScreenSamples.card, isPending: false, isSaving: false, error: nil,
                                sync: SyncStatus(text: "Hull 1–6 er synket", isPending: false),
                                onStep: { _, _ in }, onConfirm: { _ in }, onSave: {}, onGoTo: { _ in },
                                onScorecard: { _ in })
            .padding(DDSpacing.gutter)
        for width in Self.widths {
            for scheme in Self.schemes {
                var heights: [CGFloat] = []
                for size in Self.sizes {
                    let rendered = try #require(render(card, width: width, size: size, scheme: scheme))
                    #expect(rendered.width == width, "bredde \(width) \(size)")
                    heights.append(rendered.height)
                }
                #expect(heights == heights.sorted(), "høyden skal vokse med teksten ved \(width) pt: \(heights)")
                #expect(heights.last! > heights.first!)
            }
        }
    }

    @Test("Scoremerkene tegnes for alle former i begge moduser")
    func scoreBadges() throws {
        let row = HStack {
            ScoreBadge(strokes: 2, par: 4, name: .eagle)
            ScoreBadge(strokes: 3, par: 4, name: .birdie)
            ScoreBadge(strokes: 4, par: 4, name: .par)
            ScoreBadge(strokes: 5, par: 4, name: .bogey)
            ScoreBadge(strokes: 7, par: 4, name: .dobbel)
        }
        for scheme in Self.schemes {
            for size in Self.sizes {
                let rendered = try #require(render(row, width: 375, size: size, scheme: scheme))
                #expect(rendered.height > 0)
            }
        }
    }

    @Test("Knappestilene får minst 44 pt trykkflate i alle størrelser")
    func buttonHeights() throws {
        for kind in [DDButtonKind.primary, .secondary, .text, .danger] {
            for size in Self.sizes {
                let button = Button("Lagre hull 7 og gå videre") {}.buttonStyle(.dd(kind, fullWidth: true))
                let rendered = try #require(render(button, width: 375, size: size, scheme: .light))
                #expect(rendered.height >= 44, "\(kind) \(size): \(rendered.height)")
            }
        }
    }

    @Test("Formen følger brutto mot par")
    func scoreShapes() {
        #expect(ScoreShape.forGross(1, par: 3) == .doubleCircle)
        #expect(ScoreShape.forGross(3, par: 5) == .doubleCircle)
        #expect(ScoreShape.forGross(2, par: 3) == .circle)
        #expect(ScoreShape.forGross(4, par: 4) == .plain)
        #expect(ScoreShape.forGross(5, par: 4) == .square)
        #expect(ScoreShape.forGross(6, par: 4) == .doubleSquare)
        #expect(ScoreShape.forGross(9, par: 4) == .doubleSquare)
    }
}
