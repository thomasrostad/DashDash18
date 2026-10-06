import SwiftUI

/// Den grønne jakka som strektegning (`ICON_JACKET2` i PWA-en): to jakkehalvdeler med V-krage.
struct DDJacketIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        var path = Path()
        // Ytterkant: skuldre, ermer ned, bunn.
        path.move(to: p(0.5, 0.24))
        path.addLine(to: p(0.28, 0.0))
        path.addLine(to: p(0.0, 0.14))
        path.addLine(to: p(0.0, 1.0))
        path.addLine(to: p(1.0, 1.0))
        path.addLine(to: p(1.0, 0.14))
        path.addLine(to: p(0.72, 0.0))
        path.addLine(to: p(0.5, 0.24))
        // Midtsømmen.
        path.move(to: p(0.5, 0.24))
        path.addLine(to: p(0.5, 1.0))
        return path
    }
}

#Preview {
    DDJacketIcon()
        .stroke(Color.ddGold, lineWidth: 1.6)
        .frame(width: 44, height: 52)
        .padding()
        .background(Color.ddForestDeep)
}
