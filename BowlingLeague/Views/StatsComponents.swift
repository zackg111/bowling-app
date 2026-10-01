import SwiftUI

enum StatFormat {
    /// "63%", or a dash when there's nothing to count.
    static func percent(_ rate: Double?) -> String {
        rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    static func number(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
    }

    /// First-ball average, "9.28".
    static func pins(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–"
    }
}

/// A percentage as a ring, like a fitness ring.
struct RateRing: View {
    let title: String
    let rate: Double?
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: rate ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(StatFormat.percent(rate))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 110)
        .accessibilityElement(children: .combine)
    }
}

/// The ten pins from the approach, with the ones left standing filled in.
struct PinDiagram: View {
    let standing: Set<Int>
    var tint: Color = Theme.accent
    var pinSize: CGFloat = 8

    var body: some View {
        VStack(spacing: pinSize * 0.4) {
            ForEach(PinRack.rows, id: \.self) { row in
                HStack(spacing: pinSize * 0.5) {
                    ForEach(row, id: \.self) { pin in
                        Circle()
                            .fill(standing.contains(pin) ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                            .frame(width: pinSize, height: pinSize)
                    }
                }
            }
        }
        .accessibilityLabel("Leave \(PinRack.name(standing))")
    }
}

/// A spider chart of rates from 0 to 1, with an optional second set on top for Compare.
struct RadarChart: View {
    struct Axis: Identifiable {
        let title: String
        let value: Double
        var id: String { title }
    }

    let axes: [Axis]
    var comparison: [Double]? = nil
    var tint: Color = Theme.accent
    var comparisonTint: Color = Theme.secondAccent

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2 - 34
            ZStack {
                ForEach([0.25, 0.5, 0.75, 1], id: \.self) { level in
                    polygon(Array(repeating: level, count: axes.count), center: center, radius: radius)
                        .stroke(.quaternary, lineWidth: 1)
                }
                ForEach(axes.indices, id: \.self) { index in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(index, value: 1, center: center, radius: radius))
                    }
                    .stroke(.quaternary, lineWidth: 1)
                }
                if let comparison {
                    polygon(comparison, center: center, radius: radius).fill(comparisonTint.opacity(0.2))
                    polygon(comparison, center: center, radius: radius).stroke(comparisonTint, lineWidth: 2)
                }
                polygon(axes.map(\.value), center: center, radius: radius).fill(tint.opacity(0.25))
                polygon(axes.map(\.value), center: center, radius: radius).stroke(tint, lineWidth: 2)
                ForEach(axes.indices, id: \.self) { index in
                    VStack(spacing: 0) {
                        Text(axes[index].title).font(.caption2).foregroundStyle(.secondary)
                        Text(StatFormat.percent(axes[index].value)).font(.caption.weight(.bold)).monospacedDigit()
                    }
                    .fixedSize()
                    .position(point(index, value: 1, center: center, radius: radius + 20))
                }
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axes.map { "\($0.title) \(StatFormat.percent($0.value))" }.joined(separator: ", "))
    }

    private func point(_ index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(index) / Double(max(axes.count, 1)) * 2 * .pi - .pi / 2
        let length = radius * min(max(value, 0), 1)
        return CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
    }

    private func polygon(_ values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for index in values.indices {
                let p = point(index, value: values[index], center: center, radius: radius)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}

extension GameStats {
    /// The radar chart's axes. First-ball average is out of 10 pins.
    var radarAxes: [RadarChart.Axis] {
        [
            .init(title: "Strike", value: strikeRate ?? 0),
            .init(title: "Spare", value: spareRate ?? 0),
            .init(title: "Single pin", value: singlePinRate ?? 0),
            .init(title: "Clean", value: cleanRate ?? 0),
            .init(title: "1st ball", value: (firstBallAverage ?? 0) / 10),
        ]
    }
}

/// Photo, name, home center and the numbers under them, at the top of a profile.
struct ProfileHeader: View {
    let name: String
    let photo: Data?
    let center: String
    let average: Int?
    var followers: Int?
    var following: Int?

    @Environment(\.handicapRule) private var rule

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(name: name, photoData: photo, size: 76)
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? "You" : name)
                        .font(.title2.weight(.bold))
                    if !center.isEmpty {
                        Label(center, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                if let followers { count(followers, "followers") }
                if let following { count(following, "following") }
                if let average {
                    count(average, "average")
                    count(rule.perGame(average: average), "handicap")
                }
            }
        }
    }

    private func count(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A ball's photo, or a shiny ball in a color from its name.
struct BallImage: View {
    let name: String
    let photoData: Data?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let photoData, let image = PhotoCache.image(for: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors: [color.mix(with: .white, by: 0.35), color, color.mix(with: .black, by: 0.6)],
                                                 center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: size * 0.75))
                    // Finger holes.
                    ForEach([CGPoint(x: -0.12, y: -0.1), CGPoint(x: 0.12, y: -0.1), CGPoint(x: 0, y: 0.16)], id: \.x) { hole in
                        Circle().fill(.black.opacity(0.55))
                            .frame(width: size * 0.12, height: size * 0.12)
                            .offset(x: hole.x * size, y: hole.y * size)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var color: Color {
        let palette: [Color] = [.red, .purple, .blue, .teal, .orange, .pink, .indigo, .green]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}

/// A titled block on the stats page.
struct StatsSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}
