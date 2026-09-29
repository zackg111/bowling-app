import SwiftUI
import SwiftData

struct EliminatorView: View {
    let night: Night
    @Environment(\.handicapRule) private var handicap
    @Environment(\.eliminatorRule) private var rule

    private var entrants: [Entry] { night.sortedEntries.filter(\.inEliminator) }

    private var rounds: [EliminatorRound<Entry>] {
        Eliminator.run(entrants: entrants, rule: rule) { entry, game in
            entry.handicapped(game: game, handicap)
        }
    }

    var body: some View {
        List {
            Section {
                DisclosureGroup("Entered (\(entrants.count))") {
                    ForEach(night.sortedEntries) { entry in
                        Toggle(entry.bowler?.name ?? "–", isOn: Bindable(entry).inEliminator)
                    }
                }
            } footer: {
                Text("Scores include handicap. Half the field, rounded up to even, moves on each game. Top \(rule.payingPlaces(entrants: entrants.count)) cash tonight.")
            }

            ForEach(rounds, id: \.game) { round in
                Section(header(for: round)) {
                    ForEach(round.standings, id: \.item.persistentModelID) { ranked in
                        let through = round.advancing.contains(ranked.item)
                        HStack {
                            Text("\(ranked.place)").frame(width: 28, alignment: .leading)
                            Text(ranked.item.bowler?.name ?? "–")
                            Spacer()
                            Text("\(ranked.score)").monospacedDigit()
                            Image(systemName: round.isFinal ? (through ? "dollarsign.circle.fill" : "circle")
                                                            : (through ? "checkmark.circle.fill" : "circle"))
                                .foregroundStyle(through ? .green : .secondary)
                        }
                    }
                    if !round.waitingOn.isEmpty {
                        Text("Waiting on \(round.waitingOn.compactMap { $0.bowler?.name }.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .laneBackground()
    }

    private func header(for round: EliminatorRound<Entry>) -> String {
        round.isFinal ? "Game \(round.game) · top \(round.keep) cash" : "Game \(round.game) · top \(round.keep) move on"
    }
}
