import SwiftUI
import SwiftData

/// Your profile: stats, rankings against friends, and your arsenal. Built on
/// whoever is marked "This is me", plus league nights friends scored for you.
struct ProfileView: View {
    enum Page: String, CaseIterable, Identifiable {
        case stats = "Stats", ranking = "Ranking", arsenal = "Arsenal"
        var id: Self { self }
    }

    @Environment(SocialService.self) private var social
    @Query(filter: #Predicate<Bowler> { $0.isPrimary }) private var primaries: [Bowler]
    @State private var page: Page = .stats
    @State private var filter = StatsFilter()
    /// Your games, refreshed when the profile opens.
    @State private var series: [BowledSeries] = []
    @State private var editing = false
    @State private var filtering = false
    @State private var comparing = false

    var body: some View {
        Group {
            if let me = primaries.first {
                profile(me)
            } else {
                ContentUnavailableView {
                    Label("Who Are You?", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Open yourself in Bowlers and turn on This is me. Your stats, rankings and arsenal show up here.")
                }
            }
        }
        .laneBackground()
        .navigationTitle("Profile")
        .toolbar {
            NavigationLink { FriendsView() } label: {
                Label("Friends", systemImage: "person.2")
            }
            .badge(social.requests.count)
            if !primaries.isEmpty {
                Button("Edit Profile", systemImage: "gearshape") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            if let me = primaries.first { ProfileEditorView(bowler: me) }
        }
    }

    private func profile(_ me: Bowler) -> some View {
        let local = me.bowledSeries(as: social.myID ?? "local")
        // Until the shared copies come in, show what's on this device.
        let series = self.series.isEmpty ? local : self.series
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileHeader(name: social.me?.name ?? me.name, photo: me.photoData,
                              center: social.me?.center ?? "", average: me.average,
                              followers: social.status == .ready ? social.followers.count : nil,
                              following: social.status == .ready ? social.following.count : nil)
                SocialBanner(editing: $editing)

                Picker("Page", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch page {
                case .stats: StatsView(series: series, filter: filter)
                case .ranking: RankingView(mySeries: series)
                case .arsenal: ArsenalView(bowler: me, series: series)
                }
            }
            .padding()
        }
        .refreshable {
            await social.refresh()
            self.series = await social.mySeries(me, refresh: true)
        }
        .task(id: social.status) {
            self.series = await social.mySeries(me)
        }
        .safeAreaInset(edge: .bottom) {
            if page == .stats {
                HStack(spacing: 12) {
                    Button { comparing = true } label: {
                        Label("Compare", systemImage: "person.2.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(social.following.isEmpty)
                    Button { filtering = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $filtering) { StatsFilterSheet(filter: $filter, series: series) }
        .sheet(isPresented: $comparing) { ComparePicker() }
    }
}

/// What's missing before friends can see you, with a way to fix it.
private struct SocialBanner: View {
    @Environment(SocialService.self) private var social
    @Binding var editing: Bool

    var body: some View {
        switch social.status {
        case .ready, .checking:
            EmptyView()
        case .noAccount:
            banner("Sign in to iCloud in Settings to follow friends and rank with them.", systemImage: "icloud.slash")
        case .failed(let message):
            banner("Couldn't reach iCloud: \(message)", systemImage: "exclamationmark.icloud")
        case .needsProfile:
            Button { editing = true } label: {
                banner("Set up your profile so friends can find you, follow you and compare.", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.25)), in: .rect(cornerRadius: 18))
    }
}

/// Pick who to compare with.
private struct ComparePicker: View {
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(social.following) { friend in
                NavigationLink { CompareView(friend: friend) } label: {
                    ProfileRow(profile: friend)
                }
            }
            .navigationTitle("Compare With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// A friend in a list: photo, name, center and average.
struct ProfileRow: View {
    let profile: PublicProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                if !profile.center.isEmpty {
                    Text(profile.center).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if profile.average > 0 {
                Text("\(profile.average)").font(.headline).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

/// Your name, home center and photo as friends see them.
struct ProfileEditorView: View {
    @Bindable var bowler: Bowler
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Night.date, order: .reverse) private var nights: [Night]
    @State private var name = ""
    @State private var center = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AvatarPicker(bowler: bowler)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Home bowling center", text: $center)
                } footer: {
                    Text("Friends find you by name, and see your stats and the nights you've bowled: scores, centers and balls. Your league's settings and the other bowlers in it stay private.")
                }
                if social.status == .noAccount {
                    Section {
                        Label("Sign in to iCloud in Settings first.", systemImage: "icloud.slash")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .laneBackground()
            .navigationTitle(social.me == nil ? "Set Up Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || social.myID == nil)
                    }
                }
            }
            .onAppear {
                name = social.me?.name ?? bowler.name
                center = social.me?.center ?? nights.first(where: { !$0.location.isEmpty })?.location ?? ""
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let photo = bowler.photoData.flatMap { AvatarPicker.downscaled($0, maxSide: 256) }
            try await social.saveProfile(name: name, center: center, photo: photo, average: bowler.average)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
