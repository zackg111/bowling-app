import SwiftUI
import SwiftData

struct NightDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case scores = "Scores", doubles = "Doubles", eliminator = "Eliminator", island = "Island"
        var id: Self { self }
    }

    @Bindable var night: Night
    /// Opened from this bowler's history: scroll to their games and highlight them.
    var focus: Bowler? = nil
    /// Just created: put the cursor in the title so its details get filled in.
    var isNew = false
    @State private var tab: Tab = .scores
    @State private var showingAddBowlers = false
    @State private var inGame = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .scores: ScoresView(night: night, focus: focus, editDetails: isNew)
            case .doubles: DoublesView(night: night)
            case .eliminator: EliminatorView(night: night)
            case .island: IslandView(night: night)
            }
        }
        // Tap the title to rename the night.
        .navigationTitle($night.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("In-Game Mode", systemImage: "figure.bowling") { inGame = true }
                .disabled(night.sortedEntries.isEmpty)
            Button("Add Bowlers", systemImage: "person.badge.plus") { showingAddBowlers = true }
        }
        .sheet(isPresented: $showingAddBowlers) { AddBowlersToNightView(night: night) }
        .fullScreenCover(isPresented: $inGame) { InGameView(night: night) }
    }

    /// The date, and where it's bowled when that's set.
    private var subtitle: String {
        let date = night.date.formatted(.dateTime.weekday(.wide).month().day().year())
        return night.location.isEmpty ? date : "\(date) · \(night.location)"
    }
}

struct ScoresView: View {
    let night: Night
    var focus: Bowler? = nil
    var editDetails = false
    @Environment(\.modelContext) private var context
    @FocusState private var titleFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            scores
                .task {
                    // Give the list a moment to lay out before scrolling or focusing.
                    try? await Task.sleep(for: .milliseconds(150))
                    if editDetails {
                        titleFocused = true
                    } else if let focus, let entry = night.entries?.first(where: { $0.bowler == focus }) {
                        withAnimation { proxy.scrollTo(entry.persistentModelID, anchor: .center) }
                    }
                }
        }
    }

    private var scores: some View {
        List {
            Section {
                TextField("Title", text: Bindable(night).title, prompt: Text("Night title"))
                    .font(.headline)
                    .focused($titleFocused)
                    .submitLabel(.done)
                HStack {
                    Label {
                        TextField("Location", text: Bindable(night).location, prompt: Text("Bowling alley or address"))
                            .textContentType(.location)
                            .submitLabel(.done)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
                    }
                    if let url = night.mapsURL {
                        Link(destination: url) {
                            Image(systemName: "map")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open in Maps")
                    }
                }
                DatePicker("Date", selection: Bindable(night).date, displayedComponents: .date)
            }
            Section("Bowlers") {
                ForEach(night.sortedEntries) { entry in
                    let isFocus = focus != nil && entry.bowler == focus
                    EntryRow(entry: entry)
                        .id(entry.persistentModelID)
                        .listRowBackground(isFocus ? Theme.accent.opacity(0.18) : nil)
                }
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
    @Environment(\.bowledAverageAfter) private var bowledAverageAfter

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
                    let total = entry.isAbsent ? entry.islandSeries(rule) : entry.totalWithHandicap(rule)
                    Text("\(total)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: total)
                    Text("with hcp")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.isAbsent {
                Label("Absent · blind \(entry.blindScore) a game, counted on the Island only", systemImage: "person.fill.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    gameField("G1", $entry.game1)
                    gameField("G2", $entry.game2)
                    gameField("G3", $entry.game3)
                }
                if let balls = entry.bowler?.activeBalls, !balls.isEmpty {
                    BallMenu(entry: entry, balls: balls)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: entry.games) {
            entry.bowler?.followBowledAverage(after: bowledAverageAfter)
        }
    }

    private func gameField(_ title: String, _ value: Binding<Int?>) -> some View {
        let isBig = (value.wrappedValue ?? 0) >= 200
        return GameScoreField(title: title, score: value)
            .multilineTextAlignment(.center)
            .font(.headline.monospacedDigit())
            .foregroundStyle(isBig ? Theme.strike : Color.primary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(isBig ? .regular.tint(Theme.strike.opacity(0.25)) : .regular, in: .capsule)
    }
}

/// Which ball from their arsenal they threw tonight.
private struct BallMenu: View {
    let entry: Entry
    let balls: [Ball]

    var body: some View {
        let current = entry.ball(for: 1)
        Menu {
            Picker("Ball", selection: Binding(get: { current }, set: { entry.setBall($0) })) {
                Text("None").tag(String?.none)
                ForEach(balls) { Text($0.name).tag(Optional($0.name)) }
                // A ball since retired or renamed still shows.
                if let current, !balls.contains(where: { $0.name == current }) {
                    Text(current).tag(Optional(current))
                }
            }
        } label: {
            Label(current ?? "Pick a ball", systemImage: "circle.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(current == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
        }
        .buttonStyle(.borderless)
    }
}

/// A game score box that only takes 0–300: a keystroke that would go past
/// a perfect game is refused on the spot.
struct GameScoreField: View {
    let title: String
    @Binding var score: Int?
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .onAppear { text = score.map(String.init) ?? "" }
            .onChange(of: text) { old, new in
                let digits = String(new.filter(\.isWholeNumber).prefix(3))
                if let value = Int(digits), value > GameSheet.perfectGame {
                    text = old
                } else if digits != new {
                    text = digits
                } else {
                    score = Int(digits)
                }
            }
            // Keep up with scores set elsewhere, like a finished in-game sheet.
            .onChange(of: score) { _, new in
                if new != Int(text) { text = new.map(String.init) ?? "" }
            }
    }
}

struct AddBowlersToNightView: View {
    let night: Night
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bowler.name) private var bowlers: [Bowler]
    @State private var selected: Set<PersistentIdentifier> = []

    private var available: [Bowler] {
        let already = Set((night.entries ?? []).compactMap { $0.bowler?.persistentModelID })
        return bowlers.filter { $0.isActive && !already.contains($0.persistentModelID) }
    }

    var body: some View {
        // Worked out once per redraw; every tap on a row redraws the list.
        let available = self.available
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
