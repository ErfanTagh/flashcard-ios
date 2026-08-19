import SwiftUI

/// The two halves of the open-book mark in `recallcards-icon.svg`, as separate
/// shapes so the intro can draw and swing them independently.
///
/// Coordinates are the SVG's own 120×120 space, scaled to whatever frame the
/// view gets, which keeps them checkable against the original file.
struct BookPageShape: Shape {
    enum Side { case left, right }

    let side: Side
    /// Draws the top rule along with the left page, so the mark reads as one
    /// object when both halves are stroked together.
    var includesTopRule = false

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 120
        let originX = rect.midX - 60 * scale
        let originY = rect.midY - 60 * scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        switch side {
        case .left:
            path.move(to: p(40, 35))
            path.addLine(to: p(40, 85))
            path.addLine(to: p(60, 75))
            path.addLine(to: p(60, 25))
            path.closeSubpath()
        case .right:
            path.move(to: p(60, 25))
            path.addLine(to: p(60, 75))
            path.addLine(to: p(80, 85))
            path.addLine(to: p(80, 35))
            path.closeSubpath()
        }

        if includesTopRule {
            path.move(to: p(40, 35))
            path.addLine(to: p(80, 35))
        }
        return path
    }
}

/// The full app mark: gradient rounded square with the white book on top.
///
/// `drawProgress` trims the strokes (0 = nothing drawn, 1 = complete) and
/// `spread` swings the pages open around the spine, both of which the intro
/// animates. At the defaults it renders exactly like the SVG.
struct RecallCardsLogo: View {
    var size: CGFloat = 120
    var drawProgress: CGFloat = 1
    var spread: Double = 0
    var cornerScale: CGFloat = 20 / 120

    /// The SVG's stroke is 3/120 of the canvas, which lands under a point at
    /// toolbar sizes and renders as a grey smudge. Floored so the mark stays
    /// legible small.
    private var lineWidth: CGFloat { max(size * 3 / 120, 1.5) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerScale, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: size * 100 / 120, height: size * 100 / 120)

            page(.left, includesTopRule: true)
                .rotation3DEffect(.degrees(spread), axis: (x: 0, y: 1, z: 0),
                                  anchor: .center, perspective: 0.4)

            page(.right, includesTopRule: false)
                .rotation3DEffect(.degrees(-spread), axis: (x: 0, y: 1, z: 0),
                                  anchor: .center, perspective: 0.4)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Recall Cards")
    }

    private func page(_ side: BookPageShape.Side, includesTopRule: Bool) -> some View {
        BookPageShape(side: side, includesTopRule: includesTopRule)
            .trim(from: 0, to: drawProgress)
            .stroke(.white, style: StrokeStyle(lineWidth: lineWidth,
                                               lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 40) {
        RecallCardsLogo(size: 140)
        RecallCardsLogo(size: 140, drawProgress: 0.6, spread: 25)
    }
    .padding()
    .background(Theme.background)
}
