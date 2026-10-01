import SwiftUI
import SwiftData
import Charts

/// You and a friend side by side, over the same filter.
struct CompareView: View {
    let friend: PublicProfile
    @Environment(SocialService.self) private var social
    @Query(filter: #Predicate<Bowler> { $0.isPrimary }) private var primaries: [Bowler]
    @State private var mine: [BowledSeries] = []
    @State private var theirs: [BowledSeries] = []
    @State private var filter = StatsFilter()
    @State private var filtering = false
    @State private var error: String?

    private var myName: String { social.me?.name ?? primaries.first?.name ?? "You" }

    var body: some View {
        let myGames = filter.games(from: mine)
        let theirGames = filter.games(from: theirs)
        let me = GameStats(games: myGames)
        let them = GameStats(games: theirGames)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    person(myName, photo: primaries.first?.photoData, tint: Theme.accent)
                    Text("vs").font(.headline).foregroundStyle(.secondary)
                    person(friend.name, photo: friend.photo, tint: Theme.secondAccent)
                }
                Label(filter.summary, systemImage: "line.3.horizontal.decrease")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                StatsSection(title: "Score") {
                    Chart {
                        ForEach(Array(myGames.enumerated()), id: \.offset) { index, game in
                            LineMark(x: .value("Game", index + 1), y: .value("Score", game.score), series: .value("Bowler", "You"))
                                .foregroundStyle(by: .value("Bowler", "You"))
                        }
                        ForEach(Array(theirGames.enumerated()), id: \.offset) { index, game in
                            LineMark(x: .value("Game", index + 1), y: .value("Score", game.score), series: .value("Bowler", friend.name))
                                .foregroundStyle(by: .value("Bowler", friend.name))
                        }
                    }
                    // "You" rather than your name, in case you and your friend share one.
                    .chartForegroundStyleScale(["You": Theme.accent, friend.name: Theme.secondAccent])
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                    .frame(height: 180)
                    .padding(12)
                    .glassEffect(in: .rect(cornerRadius: 20))
                }

                StatsSection(title: "Head to head") {
                    Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                        row("Average", me.average.map(Double.init), them.average.map(Double.init), StatFormat.number(me.average), StatFormat.number(them.average))
                        row("High game", me.highGame.map(Double.init), them.highGame.map(Double.init), StatFormat.number(me.highGame), StatFormat.number(them.highGame))
                        row("200+ games", Double(me.games200Plus), Double(them.games200Plus), "\(me.games200Plus)", "\(them.games200Plus)")
                        if me.hasSheets || them.hasSheets {
                            row("1st ball avg", me.firstBallAverage, them.firstBallAverage, StatFormat.pins(me.firstBallAverage), StatFormat.pins(them.firstBallAverage))
                            rate("Strikes", me.strikeRate, them.strikeRate)
                            rate("Spares", me.spareRate, them.spareRate)
                            rate("Single pins", me.singlePinRate, them.singlePinRate)
                            rate("Clean", me.cleanRate, them.cleanRate)
                            rate("Splits", me.splitRate, them.splitRate, lowerIsBetter: true)
                            rate("Strike on strike", me.strikeAfterStrikeRate, them.strikeAfterStrikeRate)
                        }
                        row("Games", nil, nil, "\(me.games)", "\(them.games)")
                    }
                    .padding(16)
                    .glassEffect(in: .rect(cornerRadius: 20))
                }

                if me.hasSheets && them.hasSheets {
                    StatsSection(title: "Radar chart") {
                        RadarChart(axes: me.radarAxes, comparison: them.radarAxes.map(\.value))
                            .padding(12)
                            .glassEffect(in: .rect(cornerRadius: 20))
                        HStack(spacing: 16) {
                            Label(myName, systemImage: "circle.fill").foregroundStyle(Theme.accent)
                            Label(friend.name, systemImage: "circle.fill").foregroundStyle(Theme.secondAccent)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding()
        }
        .laneBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Filter", systemImage: "line.3.horizontal.decrease") { filtering = true }
        }
        .sheet(isPresented: $filtering) { StatsFilterSheet(filter: $filter, series: mine + theirs) }
        .task {
            if let bowler = primaries.first { mine = await social.mySeries(bowler) }
            do {
                theirs = try await social.series(for: friend)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func person(_ name: String, photo: Data?, tint: Color) -> some View {
        VStack(spacing: 6) {
            AvatarView(name: name, photoData: photo, size: 60)
                .overlay(Circle().stroke(tint, lineWidth: 3))
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func rate(_ title: String, _ mine: Double?, _ theirs: Double?, lowerIsBetter: Bool = false) -> some View {
        row(title, mine, theirs, StatFormat.percent(mine), StatFormat.percent(theirs), lowerIsBetter: lowerIsBetter)
    }

    /// One stat, with the better side highlighted.
    private func row(_ title: String, _ mine: Double?, _ theirs: Double?, _ myText: String, _ theirText: String,
                     lowerIsBetter: Bool = false) -> some View {
        let myWin = mine.flatMap { m in theirs.map { lowerIsBetter ? m < $0 : m > $0 } } ?? false
        let theirWin = mine.flatMap { m in theirs.map { lowerIsBetter ? $0 < m : $0 > m } } ?? false
        return GridRow {
            Text(myText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(myWin ? Theme.accent : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(theirText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(theirWin ? Theme.secondAccent : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
