import SwiftUI

/// Colors and shared styling. Rounded type, a warm "lane light" accent, and a
/// soft mesh-gradient backdrop that Liquid Glass surfaces sit on.
enum Theme {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.24)      // lane-light orange
    static let secondAccent = Color(red: 0.45, green: 0.36, blue: 0.98) // ball violet
    static let strike = Color(red: 0.98, green: 0.76, blue: 0.18)       // 200+ games
}

/// A bowling lane behind every screen: maple boards running up to the pins,
/// with gutters, the aiming dots and arrows. It's a still drawing (a Canvas
/// only redraws when its size or the color scheme changes); animating the
/// background made every glass surface on top redraw and stutter.
struct LaneBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let base: Color = dark ? Color(white: 0.06) : Color(white: 0.97)
        Canvas { context, size in
            LaneDrawing(dark: dark).draw(in: &context, size: size)
        }
        // Fade to the page color under the title, and a little above the tab bar.
        .overlay {
            LinearGradient(stops: [
                .init(color: base, location: 0),
                .init(color: base.opacity(0.85), location: 0.1),
                .init(color: base.opacity(0), location: 0.24),
                .init(color: base.opacity(0), location: 0.82),
                .init(color: base.opacity(0.5), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .background(base)
        .ignoresSafeArea()
    }
}

/// The lane, seen from the approach. Distances are in feet from the foul
/// line (the bottom of the screen) to the pit behind the pins (the top).
private struct LaneDrawing {
    let dark: Bool

    private let laneLength = 66.0   // foul line to the pit
    private let laneWidth = 3.46    // 41.5 inches, 39 boards
    private let perspective = 3.0

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let lane = Geometry(size: size, length: laneLength, width: laneWidth, perspective: perspective)
        context.opacity = dark ? 0.9 : 0.75

        // Surround: kickbacks and the dark masking beyond the lane.
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(dark ? Color(red: 0.07, green: 0.06, blue: 0.10) : Color(red: 0.91, green: 0.89, blue: 0.95)))

        // Gutters.
        let gutter = laneWidth * 0.2
        context.fill(lane.strip(from: -laneWidth / 2 - gutter, to: laneWidth / 2 + gutter, near: 0, far: laneLength),
                     with: .color(dark ? Color(red: 0.14, green: 0.13, blue: 0.18) : Color(red: 0.66, green: 0.64, blue: 0.72)))

        // Boards, with a slight tone change from board to board like real maple.
        let boardWidth = laneWidth / 39
        let light = dark ? (0.36, 0.24, 0.14) : (0.97, 0.87, 0.69)
        let deep = dark ? (0.30, 0.19, 0.11) : (0.93, 0.80, 0.60)
        for board in 0..<39 {
            let t = Double((board * 37 + 11) % 9) / 8
            let tone = Color(red: light.0 + (deep.0 - light.0) * t,
                             green: light.1 + (deep.1 - light.1) * t,
                             blue: light.2 + (deep.2 - light.2) * t)
            let left = -laneWidth / 2 + Double(board) * boardWidth
            context.fill(lane.strip(from: left, to: left + boardWidth, near: 0, far: 60), with: .color(tone))
            context.stroke(lane.strip(from: left, to: left + boardWidth, near: 0, far: 60),
                           with: .color(.black.opacity(dark ? 0.25 : 0.07)), lineWidth: 0.5)
        }

        // Pin deck and pit.
        context.fill(lane.strip(from: -laneWidth / 2, to: laneWidth / 2, near: 59, far: laneLength),
                     with: .color(dark ? Color(red: 0.40, green: 0.29, blue: 0.18) : Color(red: 0.98, green: 0.92, blue: 0.80)))

        // Oil shine down the middle, and a warm lane light over the pins.
        let laneRect = lane.strip(from: -laneWidth / 2, to: laneWidth / 2, near: 0, far: laneLength).boundingRect
        context.fill(lane.strip(from: -laneWidth / 2, to: laneWidth / 2, near: 0, far: 60),
                     with: .linearGradient(Gradient(colors: [.clear, .white.opacity(dark ? 0.07 : 0.22), .clear]),
                                           startPoint: CGPoint(x: laneRect.minX, y: 0), endPoint: CGPoint(x: laneRect.maxX, y: 0)))
        let pinSpot = lane.point(lateral: 0, distance: 61)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Theme.accent.opacity(dark ? 0.35 : 0.22), .clear]),
                                           center: pinSpot, startRadius: 0, endRadius: size.width * 0.5))

        // Aiming dots at 7 feet, boards 3, 5, 8, 11 and 14 from each edge.
        let dotColor = dark ? Color(red: 0.12, green: 0.07, blue: 0.04) : Color(red: 0.45, green: 0.28, blue: 0.15)
        for board in [3, 5, 8, 11, 14, 26, 29, 32, 35, 37] {
            let center = lane.point(lateral: lane.lateral(board: board, boardWidth: boardWidth), distance: 7)
            let r = lane.feetToPoints(at: 7) * boardWidth * 0.45
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.5, width: r * 2, height: r)),
                         with: .color(dotColor.opacity(0.7)))
        }

        // Arrows: every fifth board, the middle one farthest down the lane.
        for (board, distance) in [(5, 12.0), (10, 13.0), (15, 14.0), (20, 15.0), (25, 14.0), (30, 13.0), (35, 12.0)] {
            let x = lane.lateral(board: board, boardWidth: boardWidth)
            var arrow = Path()
            arrow.move(to: lane.point(lateral: x, distance: distance + 1.4))
            arrow.addLine(to: lane.point(lateral: x + boardWidth * 0.9, distance: distance))
            arrow.addLine(to: lane.point(lateral: x - boardWidth * 0.9, distance: distance))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(Theme.accent.opacity(0.85)))
        }

        // The ten pins, back row first so nearer pins overlap farther ones.
        let rows: [(distance: Double, offsets: [Double])] = [
            // Rows spaced a little wider than real so they read as four rows.
            (63.9, [-1.5, -0.5, 0.5, 1.5]), (62.6, [-1, 0, 1]), (61.3, [-0.5, 0.5]), (60, [0]),
        ]
        for row in rows {
            for offset in row.offsets {
                drawPin(in: &context, base: lane.point(lateral: offset, distance: row.distance),
                        height: lane.feetToPoints(at: row.distance) * 1.25)
            }
        }
    }

    private func drawPin(in context: inout GraphicsContext, base: CGPoint, height h: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x * h, y: base.y - h + y * h) }
        var pin = Path()
        pin.move(to: p(0, 0))
        pin.addCurve(to: p(0.105, 0.11), control1: p(0.07, 0), control2: p(0.105, 0.05))
        pin.addCurve(to: p(0.06, 0.28), control1: p(0.105, 0.19), control2: p(0.065, 0.22))
        pin.addCurve(to: p(0.18, 0.63), control1: p(0.055, 0.38), control2: p(0.18, 0.46))
        pin.addCurve(to: p(0.085, 1.0), control1: p(0.18, 0.80), control2: p(0.12, 0.93))
        pin.addLine(to: p(-0.085, 1.0))
        pin.addCurve(to: p(-0.18, 0.63), control1: p(-0.12, 0.93), control2: p(-0.18, 0.80))
        pin.addCurve(to: p(-0.06, 0.28), control1: p(-0.18, 0.46), control2: p(-0.055, 0.38))
        pin.addCurve(to: p(-0.105, 0.11), control1: p(-0.065, 0.22), control2: p(-0.105, 0.19))
        pin.addCurve(to: p(0, 0), control1: p(-0.105, 0.05), control2: p(-0.07, 0))
        pin.closeSubpath()

        context.fill(pin, with: .linearGradient(Gradient(colors: [Color(white: 0.78), .white, Color(white: 0.85)]),
                                                startPoint: p(-0.18, 0.5), endPoint: p(0.18, 0.5)))
        var stripes = context
        stripes.clip(to: pin)
        for y in [0.22, 0.28] {
            stripes.fill(Path(CGRect(x: base.x - h * 0.2, y: base.y - h + y * h, width: h * 0.4, height: h * 0.035)),
                         with: .color(Color(red: 0.86, green: 0.12, blue: 0.16)))
        }
    }

    /// Maps lane coordinates (feet across from the middle, feet down the lane)
    /// to the screen, narrowing toward the pins.
    private struct Geometry {
        let size: CGSize
        let length: Double
        let width: Double
        let perspective: Double

        private var nearY: CGFloat { size.height * 1.02 }
        private var farY: CGFloat { size.height * 0.27 }
        private var nearHalfWidth: CGFloat { size.width * 0.58 }
        private var farHalfWidth: CGFloat { size.width * 0.16 }

        func y(distance: Double) -> CGFloat {
            let k = perspective
            let f = (1 / (1 + k * distance / length) - 1 / (1 + k)) / (1 - 1 / (1 + k))
            return farY + (nearY - farY) * f
        }

        func halfWidth(atY y: CGFloat) -> CGFloat {
            let t = (y - farY) / (nearY - farY)
            return farHalfWidth + (nearHalfWidth - farHalfWidth) * t
        }

        func feetToPoints(at distance: Double) -> CGFloat {
            halfWidth(atY: y(distance: distance)) / (width / 2)
        }

        func point(lateral: Double, distance: Double) -> CGPoint {
            let y = y(distance: distance)
            return CGPoint(x: size.width / 2 + lateral / (width / 2) * halfWidth(atY: y), y: y)
        }

        func lateral(board: Int, boardWidth: Double) -> Double {
            -width / 2 + (Double(board) - 0.5) * boardWidth
        }

        /// A band running down the lane between two lateral positions.
        func strip(from left: Double, to right: Double, near: Double, far: Double) -> Path {
            var path = Path()
            path.move(to: point(lateral: left, distance: near))
            path.addLine(to: point(lateral: right, distance: near))
            path.addLine(to: point(lateral: right, distance: far))
            path.addLine(to: point(lateral: left, distance: far))
            path.closeSubpath()
            return path
        }
    }
}

extension View {
    /// Puts a list or form on the lane background.
    func laneBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { LaneBackground() }
    }
}

/// A big number with a caption, on glass.
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 18))
    }
}
