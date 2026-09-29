import SwiftUI
import SwiftData

struct NightDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case scores = "Scores", doubles = "Doubles", eliminator = "Eliminator", island = "Island"
        var id: Self { self }
    }

    @Bindable var night: Night
    @State private var tab: Tab = .scores
    @State private var showingAddBowlers = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .scores: ScoresView(night: night)
            case .doubles: DoublesView(night: night)
            case .eliminator: EliminatorView(night: night)
            case .island: IslandView(night: night)
            }
        }
        .navigationTitle(night.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Add Bowlers", systemImage: "person.badge.plus") { showingAddBowlers = true }
        }
        .sheet(isPresented: $showingAddBowlers) { AddBowlersToNightView(night: night) }
    }
}

struct ScoresView: View {
    let night: Night
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                DatePicker("Date", selection: Bindable(night).date, displayedComponents: .date)
            }
            Section("Bowlers") {
                ForEach(night.sortedEntries) { EntryRow(entry: $0) }
                    .onDelete { offsets in
                        let entries = night.sortedEntries
                        for index in offsets { context.delete(entries[index]) }
                    }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .laneBackground()
    }
}

struct EntryRow: View {
    @Bindable var entry: Entry
    @Environment(\.handicapRule) private var rule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let bowler = entry.bowler {
                    AvatarView(bowler: bowler, size: 32)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.bowler?.name ?? "–").font(.headline)
                    Text("Avg \(entry.average) · Hcp \(rule.series(average: entry.average))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(entry.totalWithHandicap(rule))")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: entry.totalWithHandicap(rule))
                    Text("with hcp")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                gameField("G1", $entry.game1)
                gameField("G2", $entry.game2)
                gameField("G3", $entry.game3)
            }
        }
        .padding(.vertical, 4)
    }

    private func gameField(_ title: String, _ value: Binding<Int?>) -> some View {
        let isBig = (value.wrappedValue ?? 0) >= 200
        return TextField(title, value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.headline.monospacedDigit())
            .foregroundStyle(isBig ? Theme.strike : Color.primary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(isBig ? .regular.tint(Theme.strike.opacity(0.25)) : .regular, in: .capsule)
    }
}

struct AddBowlersToNightView: View {
    let night: Night
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bowler.name) private var bowlers: [Bowler]
    @State private var selected: Set<PersistentIdentifier> = []

    private var available: [Bowler] {
        let already = Set(night.entries.compactMap { $0.bowler?.persistentModelID })
        return bowlers.filter { $0.isActive && !already.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            List(available, selection: $selected) { bowler in
                HStack {
                    AvatarView(bowler: bowler, size: 28)
                    Text(bowler.name)
                    Spacer()
                    Text("\(bowler.average)").foregroundStyle(.secondary)
                }
                .tag(bowler.persistentModelID)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Who's Bowling?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        for bowler in available where selected.contains(bowler.persistentModelID) {
                            context.insert(Entry(bowler: bowler, night: night))
                        }
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
