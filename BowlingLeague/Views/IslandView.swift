import SwiftUI
import SwiftData

struct IslandView: View {
    let night: Night
    @Environment(\.handicapRule) private var rule
    @Environment(\.modelContext) private var context
    @AppStorage("islandWeeks") private var islandWeeks = 1
    @Query(sort: \Bowler.name) private var bowlers: [Bowler]
    @Query(sort: \Night.date) private var nights: [Night]

    /// Tonight and the nights since the last recorded elimination.
    private var round: IslandRound<Night> {
        let upToTonight = nights.filter { $0.date < night.date && $0 != night } + [night]
        return Island.round(nights: upToTonight, weeks: islandWeeks) { $0.islandRecorded }
    }

    /// The bowlers on the island who aren't out for the season.
    private var participants: [Bowler] {
        bowlers.filter { $0.onIsland && $0.islandOutDate == nil }
    }

    private func entry(for bowler: Bowler) -> Entry? {
        night.entries?.first { $0.bowler == bowler }
    }

    private var castawaysTonight: [Entry] {
        night.sortedEntries.filter { $0.bowler?.isIslandCastaway == true }
    }

    private var swimmersTonight: [Entry] {
        night.sortedEntries.filter { $0.bowler?.isIslandSwimmer == true }
    }

    /// One night's Island series for a bowler: zero when they had no line that night.
    private func series(of bowler: Bowler?, on night: Night) -> Int {
        night.entries?.first { $0.bowler == bowler }?.islandSeries(rule) ?? 0
    }

    /// Everything the bowler scored across the round, or nil while tonight's games are missing.
    private func score(_ entry: Entry, over window: [Night]) -> Int? {
        entry.islandGames.contains(nil) ? nil : window.reduce(0) { $0 + series(of: entry.bowler, on: $1) }
    }

    private func tonight(over window: [Night]) -> IslandNight<Entry> {
        Island.night(
            castaways: castawaysTonight,
            swimmers: swimmersTonight,
            protected: Set(castawaysTonight.filter { $0.bowler?.hasImmunity == true })
        ) { score($0, over: window) }
    }

    var body: some View {
        let round = self.round
        let result = tonight(over: round.window)
        List {
            Section {
                ForEach(participants) { bowler in
                    HStack {
                        Text(bowler.name)
                        if bowler.hasImmunity {
                            Image(systemName: "shield.fill").foregroundStyle(.blue)
                        }
                        if bowler.isIslandSwimmer {
                            Image(systemName: "figure.pool.swim").foregroundStyle(.teal)
                        }
                        Spacer()
                        Text("Absent").foregroundStyle(.secondary)
                        Toggle("Absent", isOn: absent(bowler)).labelsHidden()
                    }
                }
                if participants.isEmpty {
                    Text("Nobody is on the Island yet. Turn it on from a bowler's page.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On the Island (\(bowlers.filter(\.isIslandCastaway).count) castaways)")
            } footer: {
                Text("An absent bowler is scored a blind game of their average minus 10 pins, three times over. It only counts here: it never touches their average or any other game. A swimmer who is absent still needs the highest series to get back on.")
            }

            Section {
                if round.weeks > 1 {
                    Text(round.isElimination
                         ? "Final week of \(round.weeks). Scores add up tonight and the \(round.window.count - 1) before it."
                         : "Week \(round.week) of \(round.weeks). Nobody is voted off until week \(round.weeks); scores keep adding up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(result.standings, id: \.item.persistentModelID) { ranked in
                    HStack {
                        Text("\(ranked.place)").frame(width: 28, alignment: .leading)
                        Text(ranked.item.bowler?.name ?? "–")
                        if ranked.item.isAbsent {
                            Text("blind").font(.caption).foregroundStyle(.secondary)
                        }
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
            } header: {
                Text(round.weeks > 1 ? "Week \(round.week) of \(round.weeks) totals" : "Tonight")
            } footer: {
                Text("High series wins immunity for next week. Low series goes swimming, and gets back on only by bowling the highest series.")
            }

            if result.isComplete && (round.isElimination || night.islandRecorded) {
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

    /// The Absent switch. Turning it on for someone with no line tonight
    /// puts them on the night first, so the blind score has somewhere to live.
    private func absent(_ bowler: Bowler) -> Binding<Bool> {
        Binding {
            entry(for: bowler)?.isAbsent ?? false
        } set: { isAbsent in
            let line = entry(for: bowler) ?? {
                let created = Entry(bowler: bowler, night: night)
                context.insert(created)
                return created
            }()
            line.setAbsent(isAbsent)
        }
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
