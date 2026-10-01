import SwiftUI
import SwiftData
import PhotosUI

/// Your bowling balls, with how you bowl with each.
struct ArsenalView: View {
    @Bindable var bowler: Bowler
    let series: [BowledSeries]
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var editing: Ball?

    var body: some View {
        let all = (bowler.balls ?? []).sorted { $0.createdAt > $1.createdAt }
        let active = all.filter { !$0.isRetired }
        let retired = all.filter(\.isRetired)
        VStack(alignment: .leading, spacing: 12) {
            Text("Your arsenal").font(.title2.weight(.bold))
            if all.isEmpty {
                ContentUnavailableView("No Balls Yet", systemImage: "circle.circle",
                                       description: Text("Add your bowling balls, then pick the one you threw for each night on its Scores tab."))
            }
            ForEach(active) { row($0) }
            if !retired.isEmpty {
                Text("Retired").font(.headline).foregroundStyle(.secondary).padding(.top, 8)
                ForEach(retired) { row($0).opacity(0.6) }
            }
            Button { adding = true } label: {
                Label("Add to Arsenal", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .sheet(isPresented: $adding) { BallEditor(ball: nil, bowler: bowler) }
        .sheet(item: $editing) { BallEditor(ball: $0, bowler: bowler) }
    }

    private func row(_ ball: Ball) -> some View {
        let stats = GameStats(games: series.flatMap(\.games).filter { $0.ball == ball.name })
        return Button { editing = ball } label: {
            HStack(spacing: 14) {
                BallImage(name: ball.name, photoData: ball.photoData)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ball.name).font(.headline)
                    Text([ball.brand, ball.weight > 0 ? "\(ball.weight) lb" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let average = stats.average {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(average)").font(.headline).monospacedDigit()
                        Text("\(stats.games) games").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .contentShape(.rect)
            .glassEffect(in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(ball.isRetired ? "Bring Back" : "Retire", systemImage: ball.isRetired ? "arrow.uturn.backward" : "archivebox") {
                ball.isRetired.toggle()
            }
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(ball) }
        }
    }
}

/// Adds a ball, or edits one.
private struct BallEditor: View {
    let ball: Ball?
    let bowler: Bowler
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var weight = 15
    @State private var photo: Data?
    @State private var retired = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        // The picker's label is built off the main actor, so it gets a copy.
        let preview = BallImage(name: name, photoData: photo, size: 110)
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .images) {
                        preview
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill").padding(8).glassEffect()
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name, like Phaze II", text: $name)
                    TextField("Brand, like Storm", text: $brand)
                    Stepper(weight > 0 ? "\(weight) lb" : "Weight not set", value: $weight, in: 0...16)
                    if ball != nil {
                        Toggle("Retired", isOn: $retired)
                    }
                } footer: {
                    Text("Nights already bowled with this ball keep its name if you rename it later.")
                }
            }
            .laneBackground()
            .navigationTitle(ball == nil ? "New Ball" : "Edit Ball")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let ball else { return }
                name = ball.name
                brand = ball.brand
                weight = ball.weight
                photo = ball.photoData
                retired = ball.isRetired
            }
            .onChange(of: item) {
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photo = AvatarPicker.downscaled(data)
                    }
                }
            }
        }
    }

    private func save() {
        let target = ball ?? Ball(name: "", bowler: bowler)
        if ball == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.brand = brand.trimmingCharacters(in: .whitespaces)
        target.weight = weight
        target.photoData = photo
        target.isRetired = retired
        dismiss()
    }
}
