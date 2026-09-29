import SwiftUI

struct DoublesView: View {
    let night: Night
    @Environment(\.handicapRule) private var rule
    @State private var method: PairingMethod = .blindDraw
    @State private var confirmingRepair = false

    private var teams: [Ranked<[Entry]>] {
        let paired = night.entries.filter { $0.doublesTeam != nil }
        let grouped = Dictionary(grouping: paired) { $0.doublesTeam ?? 0 }
        return Ranking.rank(Array(grouped.values)) { team in
            team.reduce(0) { $0 + $1.totalWithHandicap(rule) }
        }
    }

    private var unpaired: [Entry] {
        night.sortedEntries.filter { $0.doublesTeam == nil }
    }

    var body: some View {
        List {
            Section {
                Picker("Pairing", selection: $method) {
                    ForEach(PairingMethod.allCases) { Text($0.label).tag($0) }
                }
                Button("Pair Teams") {
                    if teams.isEmpty { pair() } else { confirmingRepair = true }
                }
                .disabled(night.entries.count < 2)
            }

            if !teams.isEmpty {
                Section("Standings") {
                    ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                        HStack(alignment: .top) {
                            Text("\(team.place)")
                                .font(.headline)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading) {
                                ForEach(team.item) { entry in
                                    Text("\(entry.bowler?.name ?? "–")  \(entry.totalWithHandicap(rule))")
                                        .monospacedDigit()
                                }
                            }
                            Spacer()
                            Text("\(team.score)").font(.title3.bold()).monospacedDigit()
                        }
                    }
                }
            }

            if !unpaired.isEmpty && !teams.isEmpty {
                Section {
                    ForEach(unpaired) { Text($0.bowler?.name ?? "–") }
                } header: {
                    Text("Without a Partner")
                } footer: {
                    Text("Odd number of bowlers, or added after pairing.")
                }
            }
        }
        .laneBackground()
        .confirmationDialog("Re-pair every team?", isPresented: $confirmingRepair) {
            Button("Re-pair Teams", role: .destructive) { pair() }
        }
    }

    private func pair() {
        let result = DoublesPairing.pair(night.entries, average: \.average, method: method)
        for entry in night.entries {
            entry.doublesTeam = nil
            entry.doublesPartnerName = nil
        }
        for (number, (first, second)) in result.teams.enumerated() {
            first.doublesTeam = number + 1
            second.doublesTeam = number + 1
            first.doublesPartnerName = second.bowler?.name
            second.doublesPartnerName = first.bowler?.name
        }
    }
}
