import Foundation

extension Entry {
    /// This night as the stats page and friends see it. Nil when nothing was bowled.
    func bowledSeries(for profileID: String) -> BowledSeries? {
        guard let night, !isAbsent, games.contains(where: { $0 != nil }) else { return nil }
        // A sheet only counts when it's finished and matches the score kept.
        let sheets = (1...3).map { number -> GameSheet? in
            let sheet = sheet(number)
            return sheet.isComplete && game(number) == sheet.total ? sheet : nil
        }
        return BowledSeries(profileID: profileID, date: night.date, title: night.title,
                            center: night.location.trimmingCharacters(in: .whitespacesAndNewlines),
                            scores: games, sheets: sheets, balls: (1...3).map(ball(for:)))
    }
}

extension Bowler {
    /// Every night they've bowled, oldest first.
    func bowledSeries(as profileID: String) -> [BowledSeries] {
        (entries ?? []).compactMap { $0.bowledSeries(for: profileID) }.sorted { $0.date < $1.date }
    }
}
