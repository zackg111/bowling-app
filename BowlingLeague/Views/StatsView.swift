import SwiftUI
import Charts

/// The stats page for anyone's games, yours or a friend's: overview, score
/// trend, first ball, pin leaves, the radar chart and the next average tier.
struct StatsView: View {
    let series: [BowledSeries]
    let filter: StatsFilter
    @State private var showAllLeaves = false
    /// Game tapped on the score chart, 1-based.
    @State private var picked: Int?

    var body: some View {
        let games = filter.games(from: series)
        let stats = GameStats(games: games)
        VStack(alignment: .leading, spacing: 28) {
            Label(filter.summary, systemImage: "line.3.horizontal.decrease")
                .font(.caption)
                .foregroundStyle(.secondary)

            if games.isEmpty {
                ContentUnavailableView("No Games", systemImage: "chart.xyaxis.line",
                                       description: Text("Games bowled on league nights show up here."))
            } else {
                overview(stats)
                scoreChart(games, stats)
                if stats.hasSheets {
                    firstBall(stats)
                    pinLeaves(stats)
                    StatsSection(title: "Radar chart") {
                        RadarChart(axes: stats.radarAxes)
                            .padding(12)
                            .glassEffect(in: .rect(cornerRadius: 20))
                    }
                } else {
                    Label("Score games ball by ball in In-Game Mode to see first-ball stats, pin leaves and the radar chart.",
                          systemImage: "figure.bowling")
                        .font(.callout)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.2)), in: .rect(cornerRadius: 18))
                }
                if let average = stats.average, average < 291 {
                    nextTier(average)
                }
                more(stats)
            }
        }
    }

    private func overview(_ stats: GameStats) -> some View {
        StatsSection(title: "Overview") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                StatTile(title: "Average", value: StatFormat.number(stats.average), systemImage: "chart.bar.fill")
                StatTile(title: "High score", value: StatFormat.number(stats.highGame), systemImage: "flame.fill", tint: Theme.strike)
                StatTile(title: "1st ball avg", value: StatFormat.pins(stats.firstBallAverage), systemImage: "1.circle.fill", tint: Theme.secondAccent)
                StatTile(title: "Clean", value: StatFormat.percent(stats.cleanRate), systemImage: "checkmark.seal.fill")
            }
        }
    }

    private func scoreChart(_ games: [BowledGame], _ stats: GameStats) -> some View {
        let points = Array(games.enumerated())
        return StatsSection(title: "Score", trailing: "\(games.count) games") {
            Chart {
                ForEach(points, id: \.offset) { index, game in
                    LineMark(x: .value("Game", index + 1), y: .value("Score", game.score))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Game", index + 1), y: .value("Score", game.score))
                        .symbolSize(game.score >= 200 ? 30 : 14)
                        .foregroundStyle(game.score >= 200 ? Theme.strike : Theme.accent)
                }
                if let average = stats.average {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
                if let picked, points.indices.contains(picked - 1) {
                    let game = points[picked - 1].element
                    RuleMark(x: .value("Game", picked))
                        .foregroundStyle(Theme.accent.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 0) {
                                Text(game.date, format: .dateTime.month(.abbreviated).day()).font(.caption2)
                                Text("\(game.score)").font(.headline).monospacedDigit()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(in: .capsule)
                        }
                }
            }
            .foregroundStyle(Theme.accent)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartXSelection(value: $picked)
            .frame(height: 190)
            .padding(.top, 30)
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
    }

    private func firstBall(_ stats: GameStats) -> some View {
        StatsSection(title: "First ball") {
            HStack(spacing: 12) {
                RateRing(title: "Strikes", rate: stats.strikeRate, tint: Theme.strike)
                RateRing(title: "Leaves", rate: stats.leaveRate)
                RateRing(title: "Splits", rate: stats.splitRate, tint: .red)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pinLeaves(_ stats: GameStats) -> some View {
        let leaves = stats.commonLeaves
        let shown = showAllLeaves ? leaves : Array(leaves.prefix(8))
        return StatsSection(title: "Pin leaves", trailing: "picked up") {
            if leaves.isEmpty {
                Text("Tap the pins on the pin deck in In-Game Mode to see which leaves you get and how often you pick them up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(shown) { leave in
                        let split = PinRack.isSplit(leave.pins)
                        VStack(spacing: 6) {
                            PinDiagram(standing: leave.pins, tint: split ? .red : Theme.accent, pinSize: 7)
                            Text("\(leave.count.left)×").font(.caption.weight(.semibold)).monospacedDigit()
                            Text(StatFormat.percent(leave.count.rate))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(leave.count.rate >= 0.5 ? Theme.accent : .secondary)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .glassEffect(in: .rect(cornerRadius: 14))
                    }
                }
                if leaves.count > 8 {
                    Button(showAllLeaves ? "Show fewer" : "Show all \(leaves.count)") {
                        withAnimation { showAllLeaves.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func nextTier(_ average: Int) -> some View {
        let tier = AverageTier(average: average)
        let next = tier.next
        return StatsSection(title: "You vs. next tier") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(average)").font(.title.weight(.bold)).monospacedDigit()
                        Text("Your average").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(next.low)–\(next.high)").font(.title.weight(.bold)).monospacedDigit().foregroundStyle(Theme.strike)
                        Text("Next tier").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: tier.progress(average))
                    .tint(Theme.strike)
                Text("\(next.low - average) \(next.low - average == 1 ? "pin" : "pins") a game to go, about \((next.low - average) * 3) a series.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
    }

    private func more(_ stats: GameStats) -> some View {
        StatsSection(title: "More") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                StatTile(title: "Games", value: "\(stats.games)", systemImage: "circle.grid.3x3.fill")
                StatTile(title: "200+ games", value: "\(stats.games200Plus)", systemImage: "star.fill", tint: Theme.strike)
                if stats.hasSheets {
                    StatTile(title: "Spares", value: StatFormat.percent(stats.spareRate), systemImage: "line.diagonal")
                    StatTile(title: "Single pins", value: StatFormat.percent(stats.singlePinRate), systemImage: "smallcircle.filled.circle")
                    StatTile(title: "Strike on strike", value: StatFormat.percent(stats.strikeAfterStrikeRate), systemImage: "xmark", tint: Theme.strike)
                }
            }
        }
    }
}

/// Which games the stats page counts.
struct StatsFilterSheet: View {
    @Binding var filter: StatsFilter
    let centers: [String]
    let balls: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var center: String?
    @State private var ball: String?
    @State private var byDate: Bool
    @State private var count: Int
    @State private var period: StatsFilter.Period

    init(filter: Binding<StatsFilter>, series: [BowledSeries]) {
        _filter = filter
        centers = Array(Set(series.map(\.center).filter { !$0.isEmpty })).sorted()
        balls = Array(Set(series.flatMap(\.balls).compactMap { $0 })).sorted()
        let current = filter.wrappedValue
        _center = State(initialValue: current.center)
        _ball = State(initialValue: current.ball)
        switch current.span {
        case .lastGames(let count):
            _byDate = State(initialValue: false)
            _count = State(initialValue: count)
            _period = State(initialValue: .lastMonth)
        case .period(let period):
            _byDate = State(initialValue: true)
            _count = State(initialValue: 30)
            _period = State(initialValue: period)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Bowling center", selection: $center) {
                        Text("All centers").tag(String?.none)
                        ForEach(centers, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Ball", selection: $ball) {
                        Text("Any ball").tag(String?.none)
                        ForEach(balls, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                } footer: {
                    Text("Centers come from each night's location. Pick a ball for a night on its Scores tab.")
                }
                Section("Games") {
                    Picker("Count by", selection: $byDate) {
                        Text("Games").tag(false)
                        Text("Date").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if byDate {
                        Picker("Period", selection: $period) {
                            ForEach(StatsFilter.Period.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } else {
                        Stepper("Last \(count) games", value: $count, in: 5...500, step: 5)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = StatsFilter(center: center, ball: ball, span: byDate ? .period(period) : .lastGames(count))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        filter = StatsFilter()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
