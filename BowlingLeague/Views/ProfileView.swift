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
    @State private var settingUp = false

    var body: some View {
        Group {
            if let me = primaries.first {
                profile(me)
            } else {
                ContentUnavailableView {
                    Label("Set Up Your Profile", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Tell us who you are. Your stats, rankings and arsenal show up here, and friends can find you.")
                } actions: {
                    Button("Set Up Profile") { settingUp = true }
                        .buttonStyle(.glassProminent)
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
            Button("Edit Profile", systemImage: "gearshape") {
                // Nobody's marked "This is me" yet: run the full setup instead.
                if primaries.isEmpty { settingUp = true } else { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            if let me = primaries.first { ProfileEditorView(bowler: me) }
        }
        .fullScreenCover(isPresented: $settingUp) {
            OnboardingView()
        }
    }

    private func profile(_ me: Bowler) -> some View {
        let local = me.bowledSeries(as: social.myID ?? "local")
        // Until the shared copies come in, show what's on this device.
        let series = self.series.isEmpty ? local : self.series
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileHeader(name: social.me?.name ?? me.name, photo: me.photoData,
                              center: me.homeCenter.isEmpty ? social.me?.center ?? "" : me.homeCenter,
                              average: me.average, details: me.bodySummary,
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

/// Your name, home center, photo, and age, height and weight.
struct ProfileEditorView: View {
    @Bindable var bowler: Bowler
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Night.date, order: .reverse) private var nights: [Night]
    @State private var name = ""
    @State private var center = ""
    @State private var birthday: Date?
    @State private var heightInches: Int?
    @State private var weightText = ""
    @State private var sharesBodyStats = false
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
                    HomeCenterField(center: $center)
                } footer: {
                    Text("Friends find you by name, and see your stats and the nights you've bowled: scores, centers and balls. Your league's settings and the other bowlers in it stay private.")
                }

                Section {
                    if let birthday {
                        DatePicker("Birthday", selection: Binding(get: { birthday }, set: { self.birthday = $0 }),
                                   in: ...Date.now, displayedComponents: .date)
                            .swipeActions { Button("Remove", role: .destructive) { self.birthday = nil } }
                    } else {
                        Button("Add Birthday", systemImage: "birthday.cake") {
                            birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now)
                        }
                    }
                    Picker("Height", selection: $heightInches) {
                        Text("Not set").tag(Int?.none)
                        ForEach(48...90, id: \.self) { Text(BodyFormat.height($0)).tag(Optional($0)) }
                    }
                    LabeledContent("Weight") {
                        HStack(spacing: 4) {
                            TextField("Not set", text: $weightText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            if !weightText.isEmpty { Text("lb").foregroundStyle(.secondary) }
                        }
                    }
                    Toggle("Show to friends", isOn: $sharesBodyStats)
                } header: {
                    Text("About you")
                } footer: {
                    Text(sharesBodyStats
                         ? "Friends see your age (not your birthday), height and weight on your profile."
                         : "Only you see these. Turn on Show to friends to put them on your profile.")
                }

                if social.status == .noAccount {
                    Section {
                        Label("Sign in to iCloud to share your profile with friends. These are saved on this phone either way.", systemImage: "icloud.slash")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                name = social.me?.name ?? bowler.name
                center = !bowler.homeCenter.isEmpty ? bowler.homeCenter
                    : social.me?.center ?? nights.first(where: { !$0.location.isEmpty })?.location ?? ""
                birthday = bowler.birthday
                heightInches = bowler.heightInches
                weightText = bowler.weightPounds.map(String.init) ?? ""
                sharesBodyStats = bowler.sharesBodyStats
            }
            .onChange(of: weightText) { _, new in
                let digits = String(new.filter(\.isWholeNumber).prefix(3))
                if digits != new { weightText = digits }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        // Saved on your bowler first, so it's kept even without iCloud.
        bowler.name = name.trimmingCharacters(in: .whitespaces)
        bowler.homeCenter = center.trimmingCharacters(in: .whitespaces)
        bowler.birthday = birthday
        bowler.heightInches = heightInches
        bowler.weightPounds = Int(weightText).flatMap { $0 > 0 ? $0 : nil }
        bowler.sharesBodyStats = sharesBodyStats
        guard social.myID != nil else {
            dismiss()
            return
        }
        do {
            try await social.saveProfile(from: bowler)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
