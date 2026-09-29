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
    @State private var category: Category = .average

    private var standings: [Ranked<Bowler>] {
        let counted = category == .average ? bowlers : bowlers.filter { category.value(for: $0) > 0 }
        return Ranking.rank(counted.sorted { $0.name < $1.name }) { category.value(for: $0) }
    }

    var body: some View {
        let ranked = standings
        List {
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
                    Podium(top: Array(ranked.prefix(3)))
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

private struct Podium: View {
    let top: [Ranked<Bowler>]

    var body: some View {
        // Second, first, third, so the leader stands in the middle.
        let order = [1, 0, 2].filter { $0 < top.count }
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(order, id: \.self) { index in
                let row = top[index]
                NavigationLink(value: row.item) {
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
