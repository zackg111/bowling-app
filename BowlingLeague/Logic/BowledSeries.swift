import Foundation

/// One night's games for one bowler, as the stats page, rankings and friends
/// see it. It's what gets shared with friends, so it carries the games and
/// where they were bowled, and nothing else about the league.
nonisolated struct BowledSeries: Codable, Hashable, Sendable, Identifiable {
    /// The iCloud account these games belong to ("local" before there is one).
    var profileID: String
    var date: Date
    var title = ""
    /// The bowling center: the night's location.
    var center = ""
    /// Games 1–3; nil for a game not bowled.
    var scores: [Int?]
    /// Ball-by-ball sheets, for games scored in in-game mode.
    var sheets: [GameSheet?] = []
    /// The ball used for each game, by name.
    var balls: [String?] = []

    /// The same on every device: whose games, and when they were bowled.
    var id: String { "\(profileID)-\(Int(date.timeIntervalSince1970))" }

    var games: [BowledGame] {
        scores.indices.compactMap { index in
            guard let score = scores[index] else { return nil }
            return BowledGame(seriesID: id, date: date, number: index + 1, score: score,
                              sheet: sheets.indices.contains(index) ? sheets[index] : nil,
                              center: center,
                              ball: balls.indices.contains(index) ? balls[index] : nil)
        }
    }

    /// The same text for the same games, whatever order the pin sets inside
    /// happen to encode in. Used to skip re-sharing a series that hasn't changed.
    var fingerprint: String {
        var parts = [profileID, String(date.timeIntervalSince1970), title, center]
        parts += scores.map { $0.map(String.init) ?? "-" }
        parts += balls.map { $0 ?? "-" }
        parts += sheets.map { sheet in
            sheet.map { $0.rolls.map { "\($0.count):\($0.standing.map(PinRack.name) ?? "?")" }.joined(separator: ",") } ?? "-"
        }
        return parts.joined(separator: "|")
    }

    /// Series on this device first; the shared copies only fill in nights it doesn't have.
    static func merge(_ local: [BowledSeries], _ shared: [BowledSeries]) -> [BowledSeries] {
        let ids = Set(local.map(\.id))
        return (local + shared.filter { !ids.contains($0.id) }).sorted { $0.date < $1.date }
    }
}

/// One game, for the stats page.
nonisolated struct BowledGame: Hashable, Sendable {
    var seriesID: String
    var date: Date
    /// Game 1, 2 or 3 of the night.
    var number: Int
    var score: Int
    /// Only for games scored ball by ball.
    var sheet: GameSheet?
    var center: String
    var ball: String?
}
