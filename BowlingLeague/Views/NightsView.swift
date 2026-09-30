import SwiftUI
import SwiftData

struct NightsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Night.date, order: .reverse) private var nights: [Night]
    /// A night just added with +, opened right away.
    @State private var newNight: Night?
    /// Night waiting on the delete confirmation.
    @State private var deleting: Night?

    var body: some View {
        List {
            ForEach(nights) { night in
                NavigationLink(value: night) {
                    HStack(spacing: 14) {
                        VStack(spacing: 0) {
                            Text(night.date, format: .dateTime.month(.abbreviated))
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.accent)
                            Text(night.date, format: .dateTime.day())
                                .font(.title2.weight(.bold))
                        }
                        .frame(width: 52, height: 52)
                        .glassEffect(in: .rect(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(night.title).font(.headline)
                            Text("\((night.entries ?? []).count) bowlers")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !night.location.isEmpty {
                                Label(night.location, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                // No full swipe: deleting a night always asks first.
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = night }
                }
            }
        }
        .laneBackground()
        .confirmationDialog("Delete \(deleting?.title ?? "this night")?",
                            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
                            titleVisibility: .visible,
                            presenting: deleting) { night in
            Button("Delete Night", role: .destructive) {
                context.delete(night)
                deleting = nil
            }
        } message: { night in
            let bowlers = (night.entries ?? []).count
            Text("\(night.date.formatted(date: .abbreviated, time: .omitted)) and all \(bowlers) bowlers' scores, doubles and eliminator for it will be deleted. This can't be undone.")
        }
        .navigationTitle("Nights")
        .navigationDestination(for: Night.self) { NightDetailView(night: $0) }
        .navigationDestination(item: $newNight) { NightDetailView(night: $0, isNew: true) }
        .toolbar {
            Button("New Night", systemImage: "plus") {
                // Leagues usually bowl at the same place, so carry the last location over.
                let night = Night()
                night.location = nights.first?.location ?? ""
                context.insert(night)
                // Open it straight away so its details can be filled in.
                newNight = night
            }
        }
        .overlay {
            if nights.isEmpty {
                ContentUnavailableView("No Nights Yet", systemImage: "calendar",
                                       description: Text("Start a night to enter scores, pair doubles and run the eliminator."))
            }
        }
    }
}
