import SwiftUI
import SwiftData
import Charts

struct BowlerDetailView: View {
    @Bindable var bowler: Bowler
    @Environment(\.handicapRule) private var rule
    @Environment(\.bowledAverageAfter) private var bowledAverageAfter
    @Environment(\.modelContext) private var context

    private var history: [Entry] {
        (bowler.entries ?? []).sorted { ($0.night?.date ?? .distantPast) > ($1.night?.date ?? .distantPast) }
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
                Toggle("This is me", systemImage: "person.crop.circle.badge.checkmark", isOn: Binding(
                    get: { bowler.isPrimary },
                    set: { $0 ? bowler.makePrimary(in: context) : (bowler.isPrimary = false) }
                ))
                LabeledContent("Average") {
                    TextField("Average", value: $bowler.average, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Handicap", value: "\(rule.perGame(average: bowler.average)) a game, \(rule.series(average: bowler.average)) a series")
                if let after = bowledAverageAfter {
                    let toGo = after - stats.gamesBowled
                    Text(toGo > 0
                         ? "Switches to bowled average after \(after) games (\(toGo) to go)."
                         : "Average follows bowled games (\(after)+ games bowled).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let computed = stats.average, computed != bowler.average {
                    Button("Use bowled average (\(computed))") { bowler.average = computed }
                }
            }

            Section {
                Toggle("On the Island", systemImage: "leaf.fill", isOn: $bowler.onIsland)
                if bowler.onIsland {
                    if bowler.islandOutDate != nil {
                        Label("Out for the season", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    } else if bowler.isIslandSwimmer {
                        Label("Swimming. Needs the highest series to get back on.", systemImage: "figure.pool.swim").foregroundStyle(.teal)
                    } else if bowler.hasImmunity {
                        Label("Has immunity", systemImage: "shield.fill").foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("Island")
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

            if !(bowler.shots ?? []).isEmpty || bowler.isPrimary {
                MotionSection(bowler: bowler)
            }

            Section("History") {
                ForEach(history) { entry in
                    // Tap a night to jump to it, scrolled to this bowler's games.
                    if let night = entry.night {
                        NavigationLink {
                            NightDetailView(night: night, focus: bowler)
                        } label: {
                            HistoryRow(entry: entry)
                        }
                    } else {
                        HistoryRow(entry: entry)
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

/// One night in a bowler's history: date, games, series and doubles partner.
private struct HistoryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            // One partner per doubles spot; "themselves" when drawn with themselves.
            let partners = entry.partnerNames.map { $0 == entry.bowler?.name ? "themselves" : $0 }
            if !partners.isEmpty {
                Label("Doubles with \(partners.formatted(.list(type: .and)))", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Release speed and wrist rotation measured by the bowler's Apple Watch.
private struct MotionSection: View {
    let bowler: Bowler

    var body: some View {
        let motion = bowler.motionStats
        let recent = Array((bowler.shots ?? []).sorted { $0.date < $1.date }.suffix(50).enumerated())
        Section {
            if motion.shots == 0 {
                Text("Open Bowling League on your Apple Watch while you bowl. Each shot is saved here automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    StatTile(title: "Shots", value: "\(motion.shots)", systemImage: "applewatch")
                    StatTile(title: "Avg speed mph", value: MotionStats.mph(motion.averageSpeedMPH), systemImage: "speedometer", tint: Theme.secondAccent)
                    StatTile(title: "Top speed mph", value: MotionStats.mph(motion.topSpeedMPH), systemImage: "bolt.fill", tint: Theme.strike)
                    StatTile(title: "Avg wrist rpm", value: MotionStats.rpm(motion.averageWristRPM), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Chart(recent, id: \.offset) { index, shot in
                    LineMark(x: .value("Shot", index + 1), y: .value("mph", shot.releaseSpeedMPH))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Shot", index + 1), y: .value("mph", shot.releaseSpeedMPH))
                        .symbolSize(20)
                }
                .foregroundStyle(Theme.accent)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("Last \(recent.count) shots")
                .chartYAxisLabel("mph")
                .frame(height: 160)
                .padding(.vertical, 8)
            }
        } header: {
            Text("Motion")
        }
    }
}
