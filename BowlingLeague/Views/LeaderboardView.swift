import SwiftUI
import SwiftData

/// Home: who's on top of the league, with a podium for the top three.
struct LeaderboardView: View {
    enum Category: String, CaseIterable, Identifiable {
        case average = "Average", highGame = "High Game", highSeries = "High Series", twoHundreds = "200 Games"
        var id: Self { self }

        func value(for bowler: Bowler) -> Int {
            switch self {
            case .average: bowler.average
            case .highGame: bowler.stats.highGame
            case .highSeries: bowler.stats.highSeries
            case .twoHundreds: bowler.stats.games200Plus
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Bowler> { $0.isActive }) private var bowlers: [Bowler]
    @Query(filter: #Predicate<Bowler> { $0.isPrimary }) private var primaries: [Bowler]
    @Query(filter: #Predicate<Shot> { $0.bowler == nil }) private var unassignedShots: [Shot]
    @State private var category: Category = .average
    /// Bowler tapped on the podium.
    @State private var podiumPick: Bowler?

    private var standings: [Ranked<Bowler>] {
        let counted = category == .average ? bowlers : bowlers.filter { category.value(for: $0) > 0 }
        return Ranking.rank(counted.sorted { $0.name < $1.name }) { category.value(for: $0) }
    }

    var body: some View {
        let ranked = standings
        List {
            if primaries.isEmpty && !unassignedShots.isEmpty {
                Section {
                    Label("Mark yourself with This is me to keep your watch shots", systemImage: "applewatch")
                        .font(.callout.weight(.medium))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.25)), in: .rect(cornerRadius: 18))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            if let me = primaries.first {
                Section {
                    NavigationLink(value: me) {
                        YouCard(bowler: me, place: ranked.first { $0.item == me }?.place, category: category)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !bowlers.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        StatTile(title: "Bowlers", value: "\(bowlers.count)", systemImage: "person.3.fill")
                        StatTile(title: "League avg", value: "\(bowlers.map(\.average).reduce(0, +) / bowlers.count)",
                                 systemImage: "chart.bar.fill", tint: Theme.secondAccent)
                        StatTile(title: "High game", value: "\(bowlers.map(\.stats.highGame).max() ?? 0)",
                                 systemImage: "flame.fill", tint: Theme.strike)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if !ranked.isEmpty {
                Section {
                    Podium(top: Array(ranked.prefix(3))) { podiumPick = $0 }
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(ranked.dropFirst(3), id: \.item.persistentModelID) { row in
                        NavigationLink(value: row.item) {
                            HStack(spacing: 12) {
                                Text("\(row.place)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .leading)
                                AvatarView(bowler: row.item, size: 32)
                                Text(row.item.name)
                                Spacer()
                                Text("\(row.score)").font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .laneBackground()
        .navigationTitle("Leaderboard")
        .navigationDestination(for: Bowler.self) { BowlerDetailView(bowler: $0) }
        .navigationDestination(item: $podiumPick) { BowlerDetailView(bowler: $0) }
        .overlay {
            if bowlers.isEmpty {
                ContentUnavailableView {
                    Label("No Bowlers Yet", systemImage: "trophy")
                } description: {
                    Text("Load the Saturday Night Special spreadsheet, or add bowlers on the Bowlers tab.")
                } actions: {
                    Button("Load Saturday Night Special Spreadsheet") { SeedData.loadSpreadsheet(into: context) }
                        .buttonStyle(.glassProminent)
                }
            } else if ranked.isEmpty {
                ContentUnavailableView("No Scores Yet", systemImage: "trophy",
                                       description: Text("Enter a night's games to fill this leaderboard."))
            }
        }
    }
}

/// The phone owner's own line: avatar, average, place, and watch speed.
private struct YouCard: View {
    let bowler: Bowler
    let place: Int?
    let category: LeaderboardView.Category

    var body: some View {
        let motion = bowler.motionStats
        HStack(spacing: 14) {
            AvatarView(bowler: bowler, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(bowler.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(placeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(bowler.average)")
                    .font(.title.bold().monospacedDigit())
                Text("average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let latest = bowler.latestShot {
                    Label("\(MotionStats.mph(latest.releaseSpeedMPH)) mph", systemImage: "speedometer")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondAccent)
                    Text("top \(MotionStats.mph(motion.topSpeedMPH))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.12)), in: .rect(cornerRadius: 22))
    }

    private var placeText: String {
        guard let place else { return "Not ranked in \(category.rawValue) yet" }
        return "#\(place) in \(category.rawValue)"
    }
}

/// The top three. Each spot is its own button: three NavigationLinks in one
/// list row made the whole row one link, so a tap could open the wrong bowler.
private struct Podium: View {
    let top: [Ranked<Bowler>]
    let onSelect: (Bowler) -> Void

    var body: some View {
        // Second, first, third, so the leader stands in the middle.
        let order = [1, 0, 2].filter { $0 < top.count }
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(order, id: \.self) { index in
                let row = top[index]
                Button { onSelect(row.item) } label: {
                    VStack(spacing: 6) {
                        AvatarView(bowler: row.item, size: index == 0 ? 84 : 64)
                        Text(row.item.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(row.score)")
                            .font((index == 0 ? Font.title : .title3).bold().monospacedDigit())
                        Text(medal(row.place))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func medal(_ place: Int) -> String {
        switch place {
        case 1: "🥇"
        case 2: "🥈"
        case 3: "🥉"
        default: "\(place)"
        }
    }
}
