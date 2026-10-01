import Foundation

/// Which games the stats page counts: a center, a ball, and the last so many
/// games or a stretch of time.
nonisolated struct StatsFilter: Equatable, Sendable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case lastMonth = "Last month", lastYear = "Last year", allTime = "All time"
        var id: Self { self }

        func start(before now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .lastMonth: calendar.date(byAdding: .month, value: -1, to: now)
            case .lastYear: calendar.date(byAdding: .year, value: -1, to: now)
            case .allTime: nil
            }
        }
    }

    enum Span: Equatable, Sendable {
        case lastGames(Int)
        case period(Period)
    }

    var center: String?
    var ball: String?
    var span: Span = .lastGames(30)

    /// The matching games, oldest first.
    func games(from series: [BowledSeries], now: Date = .now, calendar: Calendar = .current) -> [BowledGame] {
        var games = series.flatMap(\.games)
            .filter { center == nil || $0.center == center }
            .filter { ball == nil || $0.ball == ball }
            .sorted { ($0.date, $0.number) < ($1.date, $1.number) }
        switch span {
        case .lastGames(let count):
            games = Array(games.suffix(count))
        case .period(let period):
            if let start = period.start(before: now, calendar: calendar) {
                games = games.filter { $0.date >= start }
            }
        }
        return games
    }

    /// "All centers · Last 30 games"
    var summary: String {
        var parts = [center ?? "All centers"]
        if let ball { parts.append(ball) }
        switch span {
        case .lastGames(let count): parts.append("Last \(count) games")
        case .period(let period): parts.append(period.rawValue)
        }
        return parts.joined(separator: " · ")
    }
}
