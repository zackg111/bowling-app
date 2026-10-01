import SwiftUI

/// Monthly leaderboards: you against the friends you follow, or everyone at your center.
struct RankingView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case friends = "Friends", center = "My center"
        var id: Self { self }
    }

    /// Someone on the board, with all their shared games.
    struct Person: Identifiable, Hashable {
        let id: String
        let name: String
        let photo: Data?
        let isMe: Bool
        let series: [BowledSeries]
    }

    struct Board {
        let category: LeaderMetrics.Category
        let ranked: [Ranked<Person>]
    }

    let mySeries: [BowledSeries]
    @Environment(SocialService.self) private var social
    @State private var month = Date.now
    @State private var scope: Scope = .friends
    @State private var others: [Person] = []
    @State private var loading = false
    @State private var error: String?

    private var people: [Person] {
        let me = Person(id: social.myID ?? "me", name: social.me?.name ?? "You", photo: social.me?.photo, isMe: true, series: mySeries)
        return [me] + others
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if social.status != .ready {
                ContentUnavailableView("Rank With Friends", systemImage: "trophy",
                                       description: Text("Set up your profile and follow friends to see monthly rankings."))
            } else {
                header
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                let boards = boards
                if boards.allSatisfy({ $0.ranked.isEmpty }) {
                    ContentUnavailableView("No Games This Month", systemImage: "calendar",
                                           description: Text(scope == .friends && social.following.isEmpty
                                                             ? "Follow friends from Friends to rank against them."
                                                             : "Rankings fill in as games are bowled."))
                } else {
                    ForEach(boards, id: \.category.rawValue) { board in
                        if !board.ranked.isEmpty { BoardSection(category: board.category, ranked: board.ranked) }
                    }
                }
            }
        }
        .task(id: scope) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rankings").font(.title2.weight(.bold))
                Spacer()
                Button("Previous month", systemImage: "chevron.left") { shiftMonth(-1) }
                    .labelStyle(.iconOnly)
                Text(month, format: .dateTime.month(.abbreviated).year())
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 84)
                Button("Next month", systemImage: "chevron.right") { shiftMonth(1) }
                    .labelStyle(.iconOnly)
                    .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
            }
            Picker("Who", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(social.me?.center.isEmpty ?? true)
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private var boards: [Board] {
        let metrics = people.compactMap { person in
            LeaderMetrics(series: person.series, month: month).map { (person, $0) }
        }
        return LeaderMetrics.Category.allCases.map { category in
            let scored = metrics.compactMap { person, metric in metric.value(category).map { (person, $0) } }
            let ranked = Ranking.rank(scored.sorted { $0.0.name < $1.0.name }) { $0.1 }
            return Board(category: category, ranked: ranked.map { Ranked(item: $0.item.0, score: $0.score, place: $0.place) })
        }
    }

    private func shiftMonth(_ months: Int) {
        if let date = Calendar.current.date(byAdding: .month, value: months, to: month) { month = date }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let social = self.social
            let profiles = scope == .friends ? social.following : try await social.centerProfiles()
            let loaded = try await withThrowingTaskGroup(of: (PublicProfile, [BowledSeries]).self) { group in
                for profile in profiles {
                    group.addTask { (profile, try await social.series(for: profile)) }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
            others = loaded.map { profile, series in
                Person(id: profile.id, name: profile.name, photo: profile.photo, isMe: false, series: series)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One category: the top three and where you are.
private struct BoardSection: View {
    let category: LeaderMetrics.Category
    let ranked: [Ranked<RankingView.Person>]

    var body: some View {
        let top = Array(ranked.prefix(3))
        let mine = ranked.first { $0.item.isMe }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.rawValue).font(.headline)
                Spacer()
                NavigationLink {
                    FullBoard(category: category, ranked: ranked)
                } label: {
                    Label("All", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(top, id: \.item.id) { RankRow(row: $0, category: category) }
            if let mine, !top.contains(where: { $0.item.isMe }) {
                RankRow(row: mine, category: category)
            }
        }
    }
}

private struct FullBoard: View {
    let category: LeaderMetrics.Category
    let ranked: [Ranked<RankingView.Person>]

    var body: some View {
        List {
            Section {
                ForEach(ranked, id: \.item.id) { RankRow(row: $0, category: category) }
                    .listRowBackground(Color.clear)
            } footer: {
                Text(category.explanation)
            }
        }
        .laneBackground()
        .navigationTitle(category.rawValue)
    }
}

private struct RankRow: View {
    let row: Ranked<RankingView.Person>
    let category: LeaderMetrics.Category

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.place)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(row.place == 1 ? Theme.strike : .secondary)
                .frame(width: 28)
            AvatarView(name: row.item.name, photoData: row.item.photo, size: 36)
            Text(row.item.isMe ? "\(row.item.name) (you)" : row.item.name)
                .font(.subheadline.weight(row.item.isMe ? .bold : .regular))
            Spacer()
            Text(category.format(row.score))
                .font(.headline.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(row.item.isMe ? .regular.tint(Theme.accent.opacity(0.5)) : .regular, in: .capsule)
        }
        .padding(10)
        .glassEffect(row.item.isMe ? .regular.tint(Theme.accent.opacity(0.2)) : .regular, in: .rect(cornerRadius: 16))
    }
}
