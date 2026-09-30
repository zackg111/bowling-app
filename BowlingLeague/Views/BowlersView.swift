import SwiftUI
import SwiftData
import PhotosUI

/// Every bowler with their average and handicap at a glance.
/// iPad shows a sortable table; iPhone shows a compact list.
/// Removing a bowler moves them to Former Bowlers so their history stays.
struct BowlersView: View {
    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name", average = "Average"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.handicapRule) private var rule
    @Query private var bowlers: [Bowler]
    @State private var sort: SortOrder = .average
    @State private var tableOrder = [KeyPathComparator(\Bowler.average, order: .reverse)]
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var opened: Bowler?
    @State private var selection = Set<Bowler.ID>()
    @State private var deleting: Bowler?

    private func matches(_ bowler: Bowler) -> Bool {
        searchText.isEmpty || bowler.name.localizedStandardContains(searchText)
    }

    private var active: [Bowler] { bowlers.filter { $0.isActive && matches($0) } }
    private var former: [Bowler] {
        bowlers.filter { !$0.isActive && matches($0) }.sorted { $0.name < $1.name }
    }

    private var listed: [Bowler] {
        switch sort {
        case .name: active.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .average: active.sorted { ($0.average, $1.name) > ($1.average, $0.name) }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                VStack(spacing: 0) {
                    table
                    if !former.isEmpty { formerList.frame(maxHeight: 240) }
                }
            } else {
                list
            }
        }
        .navigationTitle("Bowlers")
        .navigationDestination(item: $opened) { BowlerDetailView(bowler: $0) }
        .searchable(text: $searchText, prompt: "Find a bowler")
        .toolbar {
            if sizeClass != .regular {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Button("Add Bowler", systemImage: "plus") { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) { AddBowlerView() }
        .confirmationDialog("Delete \(deleting?.name ?? "") and all their scores?",
                            isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                if let deleting { context.delete(deleting) }
                deleting = nil
            }
        }
        .overlay {
            if bowlers.isEmpty {
                ContentUnavailableView {
                    Label("No Bowlers Yet", systemImage: "figure.bowling")
                } description: {
                    Text("Add everyone who bowls in the league.")
                } actions: {
                    Button("Add Bowler", systemImage: "plus") { showingAdd = true }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(listed) { bowler in
                    Button { opened = bowler } label: { row(bowler) }
                        .tint(.primary)
                        .swipeActions {
                            Button("Remove", systemImage: "person.fill.xmark") { bowler.isActive = false }
                                .tint(.orange)
                        }
                }
            }
            if !former.isEmpty {
                formerSection
            }
        }
        .laneBackground()
    }

    private var formerList: some View {
        List { formerSection }
    }

    private var formerSection: some View {
        Section {
            ForEach(former) { bowler in
                HStack {
                    AvatarView(bowler: bowler, size: 32).opacity(0.5)
                    Text(bowler.name).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Back") { bowler.isActive = true }
                        .buttonStyle(.bordered)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = bowler }
                }
                .contextMenu {
                    Button("Add Back", systemImage: "person.fill.checkmark") { bowler.isActive = true }
                    Button("Delete Forever", systemImage: "trash", role: .destructive) { deleting = bowler }
                }
            }
        } header: {
            Text("Former Bowlers")
        } footer: {
            Text("Removed bowlers keep their history. Add them back any time.")
        }
    }

    private func row(_ bowler: Bowler) -> some View {
        HStack(spacing: 12) {
            AvatarView(bowler: bowler, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(bowler.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if bowler.stats.gamesBowled > 0 {
                    Text("High \(bowler.stats.highGame) · \(bowler.stats.gamesBowled) games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(bowler.average)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text("hcp \(rule.series(average: bowler.average))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var table: some View {
        Table(active.sorted(using: tableOrder), selection: $selection, sortOrder: $tableOrder) {
            TableColumn("Bowler", value: \.name) { bowler in
                HStack {
                    AvatarView(bowler: bowler, size: 28)
                    Text(bowler.name)
                }
            }
            TableColumn("Average", value: \.average) { Text("\($0.average)").monospacedDigit().bold() }
            TableColumn("Handicap") { Text("\(rule.series(average: $0.average))").monospacedDigit() }
            TableColumn("Games") { Text("\($0.stats.gamesBowled)").monospacedDigit() }
            TableColumn("High Game") { Text("\($0.stats.highGame)").monospacedDigit() }
            TableColumn("High Series") { Text("\($0.stats.highSeries)").monospacedDigit() }
        }
        .contextMenu(forSelectionType: Bowler.ID.self) { ids in
            Button("Remove from League", systemImage: "person.fill.xmark") {
                for bowler in bowlers where ids.contains(bowler.id) { bowler.isActive = false }
            }
        } primaryAction: { ids in
            opened = bowlers.first { ids.contains($0.id) }
        }
    }
}

struct AddBowlerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var average: Int?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let title = photoData == nil ? "Add Photo" : "Change Photo"
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(title, systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Average", value: $average, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("New Bowler")
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        photoData = AvatarPicker.downscaled(data)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let bowler = Bowler(name: trimmedName, average: average ?? 0)
                        bowler.photoData = photoData
                        context.insert(bowler)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
