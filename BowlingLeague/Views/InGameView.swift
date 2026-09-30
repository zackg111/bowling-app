import SwiftUI
import SwiftData
import UIKit

/// Ball-by-ball scoring while the night is being bowled. Tap the pins that
/// fell (or a quick count), and it moves to the next bowler after each frame,
/// like the lanes' own scoring. A finished game becomes that bowler's score.
struct InGameView: View {
    let night: Night
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bowledAverageAfter) private var bowledAverageAfter
    @State private var game = 1
    @State private var currentID: PersistentIdentifier?
    /// Pins tapped down for the ball being entered.
    @State private var knocked: Set<Int> = []
    /// Who got each ball, so Undo can step back across bowlers.
    @State private var history: [(bowler: PersistentIdentifier, game: Int)] = []

    private var entries: [Entry] { night.sortedEntries }

    private var current: Entry? {
        entries.first { $0.persistentModelID == currentID } ?? entries.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Game", selection: $game) {
                    ForEach(1...3, id: \.self) { Text("Game \($0)").tag($0) }
                }
                .pickerStyle(.segmented)

                BowlerStrip(entries: entries, game: game, currentID: current?.persistentModelID) { entry in
                    currentID = entry.persistentModelID
                    knocked = []
                }

                if let entry = current {
                    let sheet = entry.sheet(game)
                    FrameSheet(sheet: sheet)
                    if let next = sheet.next {
                        BallEntry(next: next, knocked: $knocked,
                                  recordPins: { record(entry) { $0.knockDown(knocked) } },
                                  recordCount: { count in record(entry) { $0.knockDown(count: count) } })
                    } else {
                        finished(entry, total: sheet.total)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background { LaneBackground() }
            .navigationTitle(night.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(history.isEmpty)
                }
            }
            .onChange(of: game) { knocked = [] }
        }
        .fontDesign(.rounded)
        .tint(Theme.accent)
        // Keep the phone awake at the lanes.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func finished(_ entry: Entry, total: Int) -> some View {
        VStack(spacing: 10) {
            Text("Game \(game)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("\(total)")
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(total >= 200 ? Theme.strike : Color.primary)
            if let next = nextBowler(after: entry) {
                Button("Next: \(next.bowler?.name ?? "Bowler")", systemImage: "arrow.right") {
                    currentID = next.persistentModelID
                }
                .buttonStyle(.glassProminent)
            } else if game < 3 {
                Button("Start Game \(game + 1)", systemImage: "arrow.right") {
                    game += 1
                    currentID = entries.first?.persistentModelID
                }
                .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(in: .rect(cornerRadius: 24))
    }

    private func record(_ entry: Entry, _ change: (inout GameSheet) -> Bool) {
        var sheet = entry.sheet(game)
        let frameBefore = sheet.next?.frame
        guard change(&sheet) else { return }
        entry.setSheet(sheet, for: game)
        entry.bowler?.followBowledAverage(after: bowledAverageAfter)
        history.append((entry.persistentModelID, game))
        knocked = []
        // Frame over: on to the next bowler, like the lanes do.
        if sheet.next?.frame != frameBefore, let next = nextBowler(after: entry) {
            currentID = next.persistentModelID
        }
    }

    private func undo() {
        guard let last = history.popLast(),
              let entry = entries.first(where: { $0.persistentModelID == last.bowler }) else { return }
        var sheet = entry.sheet(last.game)
        sheet.undo()
        entry.setSheet(sheet, for: last.game)
        entry.bowler?.followBowledAverage(after: bowledAverageAfter)
        game = last.game
        currentID = last.bowler
        knocked = []
    }

    /// The next bowler in order who still has balls to throw this game.
    private func nextBowler(after entry: Entry) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) else { return nil }
        let order = entries[(index + 1)...] + entries[..<index]
        return order.first { !$0.sheet(game).isComplete }
    }
}

/// Everyone on the night, with their score so far this game.
private struct BowlerStrip: View {
    let entries: [Entry]
    let game: Int
    let currentID: PersistentIdentifier?
    let select: (Entry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        let sheet = entry.sheet(game)
                        let isCurrent = entry.persistentModelID == currentID
                        Button { select(entry) } label: {
                            VStack(spacing: 4) {
                                if let bowler = entry.bowler {
                                    AvatarView(bowler: bowler, size: 36)
                                }
                                Text(entry.bowler?.name.split(separator: " ").first.map(String.init) ?? "–")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 2) {
                                    if sheet.isComplete { Image(systemName: "checkmark.circle.fill") }
                                    Text(sheet.rolls.isEmpty ? (entry.game(game).map(String.init) ?? "–") : "\(sheet.total)")
                                        .monospacedDigit()
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(width: 64)
                            .padding(.vertical, 8)
                            .glassEffect(isCurrent ? .regular.tint(Theme.accent.opacity(0.35)) : .regular,
                                         in: .rect(cornerRadius: 16))
                            .contentShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .id(entry.persistentModelID)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// The ten frames: marks on top, running total underneath.
private struct FrameSheet: View {
    let sheet: GameSheet

    var body: some View {
        let frames = sheet.frames
        let current = sheet.next?.frame
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
                let frame = frames.indices.contains(index) ? frames[index] : nil
                VStack(spacing: 2) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 1) {
                        ForEach(0..<(index == 9 ? 3 : 2), id: \.self) { ball in
                            let mark = frame.flatMap { $0.marks.indices.contains(ball) ? $0.marks[ball] : nil } ?? ""
                            Text(mark)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(mark == "X" || mark == "/" ? Theme.accent : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 14)
                        }
                    }
                    Text(frame?.total.map(String.init) ?? " ")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .layoutPriority(index == 9 ? 1.4 : 1)
                .background(index == current ? Theme.accent.opacity(0.18) : Color.clear,
                            in: .rect(cornerRadius: 8))
            }
        }
        .padding(4)
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}

/// The pin deck and quick counts for the ball being entered.
private struct BallEntry: View {
    let next: GameSheet.NextBall
    @Binding var knocked: Set<Int>
    let recordPins: () -> Void
    let recordCount: (Int) -> Void

    private var clearsRack: Bool { knocked.count == next.pinsUp }
    private var isFreshRack: Bool { next.pinsUp == 10 }

    var body: some View {
        VStack(spacing: 14) {
            Text("Frame \(next.frame + 1) · Ball \(next.ball + 1)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let standing = next.standing {
                PinDeck(standing: standing, knocked: $knocked)
                Text("\(knocked.count) down · \(next.pinsUp - knocked.count) left")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: knocked)
                Button(action: recordPins) {
                    Text(knocked.isEmpty ? "Record Miss" : clearsRack ? (isFreshRack ? "Record Strike" : "Record Spare") : "Record \(knocked.count)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                Text("The last ball was entered as a count, so pick how many fell.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Quick entry: one tap per ball.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0...next.pinsUp, id: \.self) { count in
                    Button { recordCount(count) } label: {
                        Text(label(for: count))
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .tint(count == next.pinsUp ? Theme.accent : nil)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: knocked)
    }

    private func label(for count: Int) -> String {
        if count == 0 { return "-" }
        if count == next.pinsUp { return isFreshRack ? "X" : "/" }
        return "\(count)"
    }
}

/// The pins as seen from the bowler: back row 7–10, headpin at the front.
/// Tap a pin to knock it down; pins already down this frame are faded out.
private struct PinDeck: View {
    let standing: Set<Int>
    @Binding var knocked: Set<Int>

    private let rows = [[7, 8, 9, 10], [4, 5, 6], [2, 3], [1]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { pin in
                        pinButton(pin)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 24))
    }

    private func pinButton(_ pin: Int) -> some View {
        let isUp = standing.contains(pin)
        let isDown = knocked.contains(pin)
        return Button {
            if isDown { knocked.remove(pin) } else { knocked.insert(pin) }
        } label: {
            ZStack {
                Circle()
                    .fill(isUp && !isDown ? Color.white : Color.clear)
                    .shadow(color: .black.opacity(isUp && !isDown ? 0.25 : 0), radius: 3, y: 2)
                // The red neck stripes, seen from above.
                Circle()
                    .strokeBorder(Color(red: 0.86, green: 0.12, blue: 0.16).opacity(isUp && !isDown ? 1 : 0), lineWidth: 3)
                    .padding(9)
                Circle()
                    .strokeBorder(isDown ? Theme.accent : Color.secondary.opacity(isUp ? 0 : 0.3),
                                  style: StrokeStyle(lineWidth: 2, dash: isDown ? [] : [4, 3]))
                Text("\(pin)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isDown ? Theme.accent : isUp ? Color.black : Color.secondary.opacity(0.5))
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isUp)
        .accessibilityLabel("Pin \(pin)")
        .accessibilityValue(isDown ? "knocked down" : isUp ? "standing" : "already down")
    }
}
