import Foundation

/// A month of someone's games boiled down to what friends are ranked on.
nonisolated struct LeaderMetrics: Equatable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case highGame = "High game"
        case average = "Average"
        case bestBlock = "Best 3-game block"
        case strikeOnStrike = "Strike on strike"
        case endurance = "Endurance"
        var id: Self { self }

        var explanation: String {
            switch self {
            case .highGame: "Best single game this month."
            case .average: "Average of every game this month."
            case .bestBlock: "Best three-game series on one night."
            case .strikeOnStrike: "How often a strike follows a strike. Games scored ball by ball."
            case .endurance: "Games bowled this month."
            }
        }

        func format(_ value: Int) -> String {
            self == .strikeOnStrike ? "\(value)%" : "\(value)"
        }
    }

    var highGame = 0
    var average = 0
    /// Zero when no night had all three games.
    var bestBlock = 0
    /// Percent; nil without ball-by-ball games that had a strike to follow.
    var strikeOnStrike: Int?
    var endurance = 0

    func value(_ category: Category) -> Int? {
        switch category {
        case .highGame: highGame
        case .average: average
        case .bestBlock: bestBlock > 0 ? bestBlock : nil
        case .strikeOnStrike: strikeOnStrike
        case .endurance: endurance
        }
    }

    /// The games bowled in the month containing `month`. Nil when there were none.
    init?(series: [BowledSeries], month: Date, calendar: Calendar = .current) {
        let inMonth = series.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let stats = GameStats(games: inMonth.flatMap(\.games))
        guard let average = stats.average else { return nil }
        self.average = average
        highGame = stats.highGame ?? 0
        endurance = stats.games
        bestBlock = inMonth
            .map { $0.scores.compactMap { $0 } }
            .filter { $0.count >= 3 }
            .map { $0.prefix(3).reduce(0, +) }
            .max() ?? 0
        strikeOnStrike = stats.strikeAfterStrikeRate.map { Int(($0 * 100).rounded()) }
    }
}
