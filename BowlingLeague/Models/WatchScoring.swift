import Foundation
import SwiftData

/// Files games scored on the watch: each goes on the "This is me" bowler's
/// line for that day's night, adding them to the night (or starting the night)
/// when needed. With nobody marked yet, games wait until someone is.
enum WatchScoring {
    private static let pendingKey = "pendingWatchGames"

    static func receive(_ game: WatchGame, in context: ModelContext) {
        guard (1...3).contains(game.game) else { return }
        guard let me = try? context.fetch(FetchDescriptor<Bowler>(predicate: #Predicate { $0.isPrimary })).first else {
            hold(game)
            return
        }
        let night = night(for: game.night, in: context)
        let entry: Entry
        if let existing = (night.entries ?? []).first(where: { $0.bowler == me }) {
            entry = existing
        } else {
            entry = Entry(bowler: me, night: night)
            context.insert(entry)
        }
        entry.setSheet(game.sheet, for: game.game)
        me.followBowledAverage(after: bowledAverageAfter)
        try? context.save()
    }

    /// Files games that arrived before anyone was marked "This is me".
    static func receivePending(in context: ModelContext) {
        let games = pending
        guard !games.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        for game in games { receive(game, in: context) }
    }

    /// The night on the same day, or a new one carrying over the latest
    /// night's title and location.
    private static func night(for date: Date, in context: ModelContext) -> Night {
        let nights = (try? context.fetch(FetchDescriptor<Night>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        if let sameDay = nights.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return sameDay
        }
        let night = Night(date: date)
        if let latest = nights.first {
            night.title = latest.title
            night.location = latest.location
        }
        context.insert(night)
        return night
    }

    private static var pending: [WatchGame] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([WatchGame].self, from: data)) ?? []
    }

    /// Keeps the latest sheet for each night and game.
    private static func hold(_ game: WatchGame) {
        var games = pending.filter { $0.night != game.night || $0.game != game.game }
        games.append(game)
        UserDefaults.standard.set(try? JSONEncoder().encode(games), forKey: pendingKey)
    }

    /// The Settings › Average choice, read outside the view hierarchy.
    private static var bowledAverageAfter: Int? {
        let defaults = UserDefaults.standard
        let on = defaults.object(forKey: "useBowledAverage") as? Bool ?? true
        return on ? (defaults.object(forKey: "bowledAverageGames") as? Int ?? 9) : nil
    }
}
