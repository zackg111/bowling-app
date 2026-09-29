import SwiftUI

/// Colors and shared styling. Rounded type, a warm "lane light" accent, and a
/// soft mesh-gradient backdrop that Liquid Glass surfaces sit on.
enum Theme {
    static let accent = Color(red: 1.00, green: 0.42, blue: 0.24)      // lane-light orange
    static let secondAccent = Color(red: 0.45, green: 0.36, blue: 0.98) // ball violet
    static let strike = Color(red: 0.98, green: 0.76, blue: 0.18)       // 200+ games
}

/// A slow-moving mesh gradient behind every screen.
struct LaneBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let drift = 0.08 * sin(t / 6)
            let base: Color = colorScheme == .dark ? Color(white: 0.06) : Color(white: 0.97)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.5 - drift], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Theme.accent.opacity(colorScheme == .dark ? 0.35 : 0.22), base, Theme.secondAccent.opacity(colorScheme == .dark ? 0.30 : 0.16),
                    base, base, base,
                    Theme.secondAccent.opacity(colorScheme == .dark ? 0.22 : 0.10), base, Theme.accent.opacity(colorScheme == .dark ? 0.20 : 0.10),
                ]
            )
        }
        .ignoresSafeArea()
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
