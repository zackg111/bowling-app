import SwiftUI

/// Search everyone in the app by name or home center, and follow them.
struct FindBowlersView: View {
    @Environment(SocialService.self) private var social
    @State private var searchText = ""
    @State private var results: [PublicProfile] = []
    @State private var nearby: [PublicProfile] = []
    @State private var searching = false
    @State private var error: String?

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if query.count >= 2 {
                Section("Bowlers") {
                    ForEach(results) { profile in
                        row(profile)
                    }
                }
            } else if !nearby.isEmpty {
                Section {
                    ForEach(nearby) { profile in
                        row(profile)
                    }
                } header: {
                    Text("At your center")
                } footer: {
                    Text("Search by name or bowling center to find anyone using the app.")
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .laneBackground()
        .navigationTitle("Find Bowlers")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or bowling center")
        .overlay {
            if query.count >= 2 && results.isEmpty && !searching {
                ContentUnavailableView {
                    Label("No Bowlers Found", systemImage: "magnifyingglass")
                } description: {
                    Text("Nobody matches \"\(query)\" yet. Friends show up once they've set up a profile.")
                }
            } else if query.isEmpty && nearby.isEmpty {
                ContentUnavailableView("Find Bowlers", systemImage: "person.2.badge.plus",
                                       description: Text("Search by name or bowling center to find anyone using the app."))
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            searching = true
            defer { searching = false }
            // Wait for a pause in typing before searching.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                results = try await social.searchEveryone(query)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        .task { nearby = (try? await social.centerProfiles()) ?? [] }
    }

    private func row(_ profile: PublicProfile) -> some View {
        NavigationLink { FriendProfileView(profile: profile) } label: {
            HStack {
                ProfileRow(profile: profile)
                if social.isFollowing(profile) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Following")
                }
            }
        }
    }
}
