import SwiftUI
import SwiftData

/// Doubles for a night. Everyone has a number of spots (usually one; two puts
/// them on two teams). Spots are drawn at random or high-with-low, picked by
/// hand, or a mix: pick some teams, then draw the rest.
struct DoublesView: View {
    let night: Night
    @Environment(\.handicapRule) private var rule
    @State private var method: PairingMethod = .blindDraw
    @State private var confirmingRedraw = false
    @State private var pickingTeam = false

    private struct Team {
        let number: Int
        /// Someone teamed with themselves appears twice.
        let members: [Entry]
    }

    private var entries: [Entry] { night.sortedEntries }

    /// Every team made so far, in the order they were made.
    private var teams: [Team] {
        var members: [Int: [Entry]] = [:]
        for entry in entries {
            for number in entry.teamNumbers { members[number, default: []].append(entry) }
        }
        return members.sorted { $0.key < $1.key }.map { Team(number: $0.key, members: $0.value) }
    }

    /// One item per spot still waiting for a partner.
    private var openSpots: [Entry] {
        entries.flatMap { Array(repeating: $0, count: $0.openSpots) }
    }

    private var totalSpots: Int { entries.reduce(0) { $0 + $1.doublesSpots } }

    var body: some View {
        let teams = self.teams
        let openSpots = self.openSpots
        List {
            Section {
                Picker("Pairing", selection: $method) {
                    ForEach(PairingMethod.allCases) { Text($0.label).tag($0) }
                }
                Button(teams.isEmpty ? "Draw Teams" : "Redraw All Teams", systemImage: "shuffle") {
                    if teams.isEmpty { draw(openSpots) } else { confirmingRedraw = true }
                }
                .disabled(totalSpots < 2)
                if !teams.isEmpty && openSpots.count >= 2 {
                    Button("Draw the Other \(openSpots.count) Spots", systemImage: "shuffle") { draw(openSpots) }
                }
                Button("Pick a Team", systemImage: "person.2.badge.plus") { pickingTeam = true }
                    .disabled(openSpots.count < 2)
            } footer: {
                Text("Pick teams by hand, draw them, or pick some and draw the rest. Someone with two spots can be drawn with themselves.")
            }

            if !teams.isEmpty {
                Section {
                    let standings = Ranking.rank(teams) { team in
                        team.members.reduce(0) { $0 + $1.totalWithHandicap(rule) }
                    }
                    ForEach(standings, id: \.item.number) { row in
                        HStack(alignment: .top) {
                            Text("\(row.place)")
                                .font(.headline)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading) {
                                ForEach(Array(row.item.members.enumerated()), id: \.offset) { _, entry in
                                    Text("\(entry.bowler?.name ?? "–")  \(entry.totalWithHandicap(rule))")
                                        .monospacedDigit()
                                }
                            }
                            Spacer()
                            Text("\(row.score)").font(.title3.bold()).monospacedDigit()
                        }
                        .swipeActions {
                            Button("Break Up", systemImage: "person.2.slash", role: .destructive) {
                                breakUp(row.item.number)
                            }
                        }
                    }
                } header: {
                    Text("Standings")
                } footer: {
                    Text("Swipe a team to break it up and put both spots back.")
                }
            }

            if !openSpots.isEmpty && !teams.isEmpty {
                Section {
                    ForEach(Array(openSpots.enumerated()), id: \.offset) { _, entry in
                        Text(entry.bowler?.name ?? "–")
                    }
                } header: {
                    Text("Without a Partner")
                } footer: {
                    Text("Odd number of spots, or added after the draw.")
                }
            }

            Section {
                ForEach(entries) { entry in
                    Stepper(value: spots(for: entry), in: 0...3) {
                        HStack {
                            Text(entry.bowler?.name ?? "–")
                            Spacer()
                            Text(spotsLabel(entry.doublesSpots))
                                .foregroundStyle(entry.doublesSpots == 1 ? Color.secondary : Theme.accent)
                        }
                    }
                }
            } header: {
                Text("Spots")
            } footer: {
                Text("Give someone a second spot to put them on two teams. 0 sits them out of doubles.")
            }
        }
        .laneBackground()
        .confirmationDialog("Redraw every team?", isPresented: $confirmingRedraw) {
            Button("Redraw All Teams", role: .destructive) {
                entries.forEach { $0.leaveAllTeams() }
                draw(self.openSpots)
            }
        } message: {
            Text("Teams picked by hand are redrawn too.")
        }
        .sheet(isPresented: $pickingTeam) {
            PickTeamView(spots: openSpots) { first, second in
                makeTeam(first, second, number: nextTeamNumber)
            }
        }
    }

    private var nextTeamNumber: Int { (teams.map(\.number).max() ?? 0) + 1 }

    /// Pairs these spots into new teams, leaving teams already made alone.
    private func draw(_ spots: [Entry]) {
        let result = DoublesPairing.pair(spots, average: \.average, method: method)
        var number = nextTeamNumber
        for (first, second) in result.teams {
            makeTeam(first, second, number: number)
            number += 1
        }
    }

    private func makeTeam(_ first: Entry, _ second: Entry, number: Int) {
        first.joinTeam(number, partner: second)
        second.joinTeam(number, partner: first)
    }

    private func breakUp(_ number: Int) {
        for entry in entries where entry.teamNumbers.contains(number) {
            entry.leaveTeam(number)
        }
    }

    /// Lowering someone's spots below the teams they're on breaks up their
    /// latest teams.
    private func spots(for entry: Entry) -> Binding<Int> {
        Binding {
            entry.doublesSpots
        } set: { spots in
            entry.doublesSpots = spots
            while entry.teamNumbers.count > spots, let last = entry.teamNumbers.last {
                breakUp(last)
            }
        }
    }

    private func spotsLabel(_ spots: Int) -> String {
        switch spots {
        case 0: "Sitting out"
        case 1: "1 spot"
        default: "\(spots) spots"
        }
    }
}

/// Choose a team by hand from the spots still open. Someone with two open
/// spots can be picked twice to bowl with themselves.
private struct PickTeamView: View {
    let spots: [Entry]
    let create: (Entry, Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstID: PersistentIdentifier?
    @State private var secondID: PersistentIdentifier?

    /// Each bowler with an open spot, once.
    private var bowlers: [Entry] {
        var seen = Set<PersistentIdentifier>()
        return spots.filter { seen.insert($0.persistentModelID).inserted }
    }

    private func openSpots(_ entry: Entry) -> Int {
        spots.filter { $0.persistentModelID == entry.persistentModelID }.count
    }

    private var partners: [Entry] {
        bowlers.filter { $0.persistentModelID != firstID || openSpots($0) >= 2 }
    }

    private func entry(_ id: PersistentIdentifier?) -> Entry? {
        bowlers.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Bowler", selection: $firstID) {
                    Text("Choose").tag(PersistentIdentifier?.none)
                    ForEach(bowlers) { entry in
                        Text(entry.bowler?.name ?? "–").tag(Optional(entry.persistentModelID))
                    }
                }
                Picker("Partner", selection: $secondID) {
                    Text("Choose").tag(PersistentIdentifier?.none)
                    ForEach(partners) { entry in
                        let isSelf = entry.persistentModelID == firstID
                        Text(isSelf ? "\(entry.bowler?.name ?? "–") (themselves)" : entry.bowler?.name ?? "–")
                            .tag(Optional(entry.persistentModelID))
                    }
                }
                .disabled(firstID == nil)
            }
            .navigationTitle("Pick a Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let first = entry(firstID), let second = entry(secondID) {
                            create(first, second)
                        }
                        dismiss()
                    }
                    .disabled(entry(firstID) == nil || entry(secondID) == nil)
                }
            }
            .onChange(of: firstID) {
                if !partners.contains(where: { $0.persistentModelID == secondID }) { secondID = nil }
            }
        }
        .presentationDetents([.medium])
    }
}
