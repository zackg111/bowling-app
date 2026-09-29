import SwiftUI
import SwiftData

struct IslandView: View {
    let night: Night
    @Environment(\.handicapRule) private var rule
    @Query(sort: \Bowler.name) private var bowlers: [Bowler]

    private var castawaysTonight: [Entry] {
        night.sortedEntries.filter { $0.bowler?.isIslandCastaway == true }
    }

    private var swimmersTonight: [Entry] {
        night.sortedEntries.filter { $0.bowler?.isIslandSwimmer == true }
    }

    private var tonight: IslandNight<Entry> {
        Island.night(
            castaways: castawaysTonight,
            swimmers: swimmersTonight,
            protected: Set(castawaysTonight.filter { $0.bowler?.hasImmunity == true })
        ) { entry in
            entry.games.contains(nil) ? nil : entry.totalWithHandicap(rule)
        }
    }

    var body: some View {
        let result = tonight
        List {
            Section {
                DisclosureGroup("Castaways (\(bowlers.filter(\.isIslandCastaway).count) on the island)") {
                    ForEach(bowlers.filter { $0.isActive || $0.onIsland }) { bowler in
                        Toggle(isOn: Bindable(bowler).onIsland) {
                            HStack {
                                Text(bowler.name).strikethrough(bowler.islandOutDate != nil)
                                if bowler.isIslandSwimmer {
                                    Image(systemName: "figure.pool.swim").foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("High series wins immunity for next week. Low series goes swimming, and gets back on only by bowling the night's highest series.")
            }

            Section("Tonight") {
                ForEach(result.standings, id: \.item.persistentModelID) { ranked in
                    HStack {
                        Text("\(ranked.place)").frame(width: 28, alignment: .leading)
                        Text(ranked.item.bowler?.name ?? "–")
                        if ranked.item.bowler?.hasImmunity == true {
                            Image(systemName: "shield.fill").foregroundStyle(.blue)
                        }
                        if ranked.item.bowler?.isIslandSwimmer == true {
                            Image(systemName: "figure.pool.swim").foregroundStyle(.teal)
                        }
                        Spacer()
                        Text("\(ranked.score)").monospacedDigit()
                    }
                }
                if !result.waitingOn.isEmpty {
                    Text("Waiting on \(names(result.waitingOn))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if result.isComplete {
                Section {
                    LabeledContent("Immunity", value: names(result.immunity))
                    LabeledContent("Kicked off", value: names(result.kickedOff))
                    if !result.backOn.isEmpty {
                        LabeledContent("Back on the island", value: names(result.backOn))
                    }
                    let out = result.outForSeason.compactMap { $0.bowler?.name } + missingSwimmers.map(\.name)
                    if !out.isEmpty {
                        LabeledContent("Out for the season", value: out.joined(separator: " & "))
                    }
                    if night.islandRecorded {
                        Label("Recorded", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Record Island Results") { record(result) }
                    }
                } footer: {
                    if result.kickedOff.count > 1 || result.immunity.count > 1 {
                        Text("There's a tie. Recording applies it to everyone tied.")
                    }
                }
            }
        }
        .laneBackground()
    }

    /// Swimmers who didn't bowl tonight can't bowl the high series, so they're out.
    private var missingSwimmers: [Bowler] {
        let tonight = Set(swimmersTonight.compactMap { $0.bowler?.persistentModelID })
        return bowlers.filter { $0.isIslandSwimmer && !tonight.contains($0.persistentModelID) }
    }

    private func names(_ entries: [Entry]) -> String {
        entries.compactMap { $0.bowler?.name }.joined(separator: " & ")
    }

    private func record(_ result: IslandNight<Entry>) {
        let absent = missingSwimmers
        for bowler in bowlers { bowler.hasImmunity = false }
        for entry in result.immunity { entry.bowler?.hasImmunity = true }
        for entry in result.backOn { entry.bowler?.islandSwimming = false }
        for bowler in result.outForSeason.compactMap(\.bowler) + absent {
            bowler.islandSwimming = false
            bowler.islandOutDate = night.date
        }
        for entry in result.kickedOff { entry.bowler?.islandSwimming = true }
        night.islandRecorded = true
    }
}
