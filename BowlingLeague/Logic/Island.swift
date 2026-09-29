import Foundation

/// The "Island" tab from the spreadsheet: a season-long survivor game on
/// handicapped series.
/// - The high series among castaways wins immunity for next week.
/// - The low series among castaways (not counting last week's immunity)
///   is kicked off and goes swimming.
/// - A swimmer gets back on by bowling the highest series of the night
///   (ties count); otherwise they're off for the season. When that happens,
///   immunity still goes to the highest castaway, the next highest bowler.
nonisolated struct IslandNight<ID: Hashable> {
    let standings: [Ranked<ID>]
    /// Castaways or swimmers with a game still missing tonight.
    let waitingOn: [ID]
    let immunity: [ID]
    let kickedOff: [ID]
    let backOn: [ID]
    let outForSeason: [ID]

    var isComplete: Bool { waitingOn.isEmpty && !standings.isEmpty }
}

nonisolated enum Island {
    static func night<ID: Hashable>(
        castaways: [ID],
        swimmers: [ID] = [],
        protected: Set<ID> = [],
        series: (ID) -> Int?
    ) -> IslandNight<ID> {
        let everyone = castaways + swimmers
        let waiting = everyone.filter { series($0) == nil }
        let standings = Ranking.rank(everyone.filter { series($0) != nil }) { series($0) ?? 0 }
        guard waiting.isEmpty, !standings.isEmpty else {
            return IslandNight(standings: standings, waitingOn: waiting,
                               immunity: [], kickedOff: [], backOn: [], outForSeason: [])
        }

        let score = Dictionary(uniqueKeysWithValues: standings.map { ($0.item, $0.score) })
        let top = standings.first?.score ?? 0

        let castawayScores = castaways.compactMap { score[$0] }
        let immunity = castaways.filter { score[$0] == castawayScores.max() }

        let exposed = castaways.filter { !protected.contains($0) }
        let lowest = exposed.compactMap { score[$0] }.min()
        let kickedOff = exposed.filter { score[$0] == lowest }

        let backOn = swimmers.filter { score[$0] == top }
        let outForSeason = swimmers.filter { score[$0] != top }

        return IslandNight(standings: standings, waitingOn: [], immunity: immunity,
                           kickedOff: kickedOff, backOn: backOn, outForSeason: outForSeason)
    }
}
