import SwiftUI
import SwiftData

/// Find and follow friends, answer league link requests, and see who follows you.
struct FriendsView: View {
    @Environment(SocialService.self) private var social
    @State private var searchText = ""
    @State private var results: [PublicProfile] = []
    @State private var error: String?

    var body: some View {
        List {
            if social.status != .ready {
                ContentUnavailableView("Set Up Your Profile", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Make a profile from the gear button on Profile, then come back to find friends."))
                    .listRowBackground(Color.clear)
            } else if !searchText.isEmpty {
                Section("Bowlers") {
                    ForEach(results) { profile in
                        NavigationLink { FriendProfileView(profile: profile) } label: { ProfileRow(profile: profile) }
                    }
                    if results.isEmpty {
                        Text("Nobody by that name yet. Friends show up once they've set up a profile.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if !social.requests.isEmpty {
                    Section {
                        ForEach(social.requests) { request in
                            RequestRow(request: request, error: $error)
                        }
                    } header: {
                        Text("League requests")
                    } footer: {
                        Text("Approving lets the nights they score for you count in your stats, rankings and Compare. You can stop it any time.")
                    }
                }
                Section("Following") {
                    if social.following.isEmpty {
                        Text("Search for friends by name to follow them.").foregroundStyle(.secondary)
                    }
                    ForEach(social.following) { profile in
                        NavigationLink { FriendProfileView(profile: profile) } label: { ProfileRow(profile: profile) }
                            .swipeActions {
                                Button("Unfollow", role: .destructive) { run { try await social.unfollow(profile) } }
                            }
                    }
                }
                if !social.followers.isEmpty {
                    Section("Followers") {
                        ForEach(social.followers) { profile in
                            NavigationLink { FriendProfileView(profile: profile) } label: { ProfileRow(profile: profile) }
                        }
                    }
                }
                if !social.scorers.isEmpty {
                    Section {
                        ForEach(social.scorers) { profile in
                            ProfileRow(profile: profile)
                                .swipeActions {
                                    Button("Stop", role: .destructive) { run { try await social.revoke(profile) } }
                                }
                        }
                    } header: {
                        Text("Scoring for you")
                    } footer: {
                        Text("Their league nights count toward your stats. Swipe to stop.")
                    }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .laneBackground()
        .navigationTitle("Friends")
        .searchable(text: $searchText, prompt: "Find bowlers by name")
        .task(id: searchText) {
            // Wait for a pause in typing before searching.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                results = try await social.search(searchText)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        .refreshable { await social.loadConnections() }
        .task { await social.loadConnections() }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
}

private struct RequestRow: View {
    let request: LinkRequest
    @Binding var error: String?
    @Environment(SocialService.self) private var social

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("**\(request.scorerName)** added you to their league as \(request.bowlerName).")
            HStack {
                Button("Approve") {
                    Task {
                        do { try await social.approve(request) } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.glassProminent)
                Button("Decline") { social.decline(request) }
                    .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A friend's profile: their stats, follow, and compare.
struct FriendProfileView: View {
    let profile: PublicProfile
    @Environment(SocialService.self) private var social
    @State private var series: [BowledSeries] = []
    @State private var filter = StatsFilter()
    @State private var filtering = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileHeader(name: profile.name, photo: profile.photo, center: profile.center,
                              average: profile.average > 0 ? profile.average : nil,
                              following: profile.following.count)
                HStack(spacing: 12) {
                    if social.isFollowing(profile) {
                        Button { toggleFollow() } label: { Label("Following", systemImage: "checkmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                    } else {
                        Button { toggleFollow() } label: { Label("Follow", systemImage: "plus").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                    }
                    NavigationLink { CompareView(friend: profile) } label: {
                        Label("Compare", systemImage: "person.2.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .disabled(working || social.status != .ready)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                StatsView(series: series, filter: filter)
            }
            .padding()
        }
        .laneBackground()
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Filter", systemImage: "line.3.horizontal.decrease") { filtering = true }
        }
        .sheet(isPresented: $filtering) { StatsFilterSheet(filter: $filter, series: series) }
        .task { await load(refresh: false) }
        .refreshable { await load(refresh: true) }
    }

    private func load(refresh: Bool) async {
        do {
            series = try await social.series(for: profile, refresh: refresh)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleFollow() {
        working = true
        Task {
            defer { working = false }
            do {
                if social.isFollowing(profile) {
                    try await social.unfollow(profile)
                } else {
                    try await social.follow(profile)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Links a bowler in your league to their own account, so the nights you
/// score for them count on their profile once they approve.
struct LinkAccountView: View {
    @Bindable var bowler: Bowler
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String
    @State private var results: [PublicProfile] = []
    @State private var error: String?

    init(bowler: Bowler) {
        self.bowler = bowler
        _searchText = State(initialValue: bowler.name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { profile in
                        Button { link(profile) } label: { ProfileRow(profile: profile) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("They'll get a request under Profile › Friends. Once they approve, \(bowler.name)'s nights in your league count toward their stats. Nobody else in your league is shared.")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .laneBackground()
            .navigationTitle("Link \(bowler.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Their name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                results = (try? await social.search(searchText)) ?? []
            }
        }
    }

    private func link(_ profile: PublicProfile) {
        Task {
            do {
                try await social.requestLink(to: profile, bowlerName: bowler.name)
                bowler.profileID = profile.id
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// On a bowler's page: which friend account they're linked to.
struct LinkedAccountSection: View {
    @Bindable var bowler: Bowler
    @Environment(SocialService.self) private var social
    @Environment(\.modelContext) private var context
    @State private var linked: PublicProfile?
    @State private var linking = false

    var body: some View {
        Section {
            if bowler.profileID != nil {
                HStack(spacing: 12) {
                    if let linked {
                        ProfileRow(profile: linked)
                    } else {
                        ProgressView()
                    }
                }
                if let linked, let myID = social.myID {
                    Label(linked.trustedScorers.contains(myID) ? "Their nights here are shared with them" : "Waiting for them to approve",
                          systemImage: linked.trustedScorers.contains(myID) ? "checkmark.circle.fill" : "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Unlink", systemImage: "xmark.circle", role: .destructive) {
                    bowler.profileID = nil
                    linked = nil
                    Task { await social.shareLeague(from: context) }
                }
            } else {
                Button("Link to Their Account", systemImage: "link") { linking = true }
                    .disabled(social.status != .ready)
            }
        } header: {
            Text("Friend account")
        } footer: {
            if bowler.profileID == nil {
                Text(social.status == .ready
                     ? "If they have the app, link them so the nights you score count on their own profile."
                     : "Set up your profile under Profile to link bowlers to their accounts.")
            }
        }
        .sheet(isPresented: $linking) { LinkAccountView(bowler: bowler) }
        .task(id: bowler.profileID) {
            guard let id = bowler.profileID else { return }
            linked = try? await social.profile(id: id)
        }
    }
}
