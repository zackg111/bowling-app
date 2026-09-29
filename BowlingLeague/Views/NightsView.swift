import SwiftUI
import SwiftData

struct NightsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Night.date, order: .reverse) private var nights: [Night]

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
                            Text("\(night.entries.count) bowlers")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(nights[index]) }
            }
        }
        .laneBackground()
        .navigationTitle("Nights")
        .navigationDestination(for: Night.self) { NightDetailView(night: $0) }
        .toolbar {
            Button("New Night", systemImage: "plus") { context.insert(Night()) }
        }
        .overlay {
            if nights.isEmpty {
                ContentUnavailableView("No Nights Yet", systemImage: "calendar",
                                       description: Text("Start a night to enter scores, pair doubles and run the eliminator."))
            }
        }
    }
}
