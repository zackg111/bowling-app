import SwiftUI
import SwiftData

/// The search tab: find a bowler and jump to their stats.
struct BowlerSearchView: View {
    @Query(sort: \Bowler.name) private var bowlers: [Bowler]
    @State private var searchText = ""

    private var results: [Bowler] {
        searchText.isEmpty ? bowlers : bowlers.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        List(results) { bowler in
            NavigationLink(value: bowler) {
                HStack {
                    Text(bowler.name)
                    Spacer()
                    Text("\(bowler.average)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Search")
        .navigationDestination(for: Bowler.self) { BowlerDetailView(bowler: $0) }
        .searchable(text: $searchText, prompt: "Bowlers")
        .overlay {
            if results.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
