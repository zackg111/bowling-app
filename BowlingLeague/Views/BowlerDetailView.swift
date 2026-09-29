import SwiftUI

struct BowlerDetailView: View {
    @Bindable var bowler: Bowler
    @Environment(\.handicapRule) private var rule

    private var history: [Entry] {
        bowler.entries.sorted { ($0.night?.date ?? .distantPast) > ($1.night?.date ?? .distantPast) }
    }

    var body: some View {
        let stats = bowler.stats
        Form {
            Section {
                AvatarPicker(bowler: bowler)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Bowler") {
                TextField("Name", text: $bowler.name)
                LabeledContent("Average") {
                    TextField("Average", value: $bowler.average, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Handicap", value: "\(rule.perGame(average: bowler.average)) a game, \(rule.series(average: bowler.average)) a series")
                if let computed = stats.average, computed != bowler.average {
                    Button("Use bowled average (\(computed))") { bowler.average = computed }
                }
            }

            Section("Stats") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    StatTile(title: "Bowled avg", value: stats.average.map(String.init) ?? "–", systemImage: "chart.bar.fill")
                    StatTile(title: "High game", value: "\(stats.highGame)", systemImage: "flame.fill", tint: Theme.strike)
                    StatTile(title: "High series", value: "\(stats.highSeries)", systemImage: "trophy.fill", tint: Theme.secondAccent)
                    StatTile(title: "Games", value: "\(stats.gamesBowled)", systemImage: "circle.grid.3x3.fill")
                    StatTile(title: "Nights", value: "\(stats.nightsBowled)", systemImage: "calendar")
                    StatTile(title: "200+ games", value: "\(stats.games200Plus)", systemImage: "star.fill", tint: Theme.strike)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("History") {
                ForEach(history) { entry in
                    HStack {
                        Text(entry.night?.date ?? .now, format: .dateTime.month().day())
                        Spacer()
                        Text(entry.games.map { $0.map(String.init) ?? "–" }.joined(separator: "  "))
                            .monospacedDigit()
                        Text("\(entry.scratchSeries)")
                            .monospacedDigit()
                            .bold()
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
        }
        .laneBackground()
        .navigationTitle(bowler.name)
        .toolbar {
            Button(bowler.isActive ? "Remove from League" : "Add Back to League",
                   systemImage: bowler.isActive ? "person.fill.xmark" : "person.fill.checkmark") {
                bowler.isActive.toggle()
            }
        }
    }
}
