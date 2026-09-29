import Foundation

/// How the eliminator cuts and pays.
struct EliminatorRule: Equatable {
    var games = 3
    /// Nights with at least this many entrants pay 4 places; smaller nights pay 3.
    var fourPlacesFrom = 20

    /// Half the field moves on, rounded up to the nearest even number
    /// (25 → 14, 22 → 12, 20 → 10).
    static func advancing(from field: Int) -> Int {
        let half = (field + 1) / 2
        return half.isMultiple(of: 2) ? half : half + 1
    }

    func payingPlaces(entrants: Int) -> Int {
        entrants >= fourPlacesFrom ? 4 : 3
    }
}

/// Game-by-game eliminator on handicapped scores. Everyone entered bowls
/// game 1; half the field (rounded up to even) moves on after each game
/// but the last, and the last game's top 3 or 4 cash. Ties at a cut all move on.
struct EliminatorRound<ID: Hashable> {
    let game: Int
    let isFinal: Bool
    let standings: [Ranked<ID>]
    /// Bowlers still alive who haven't got a score entered for this game.
    let waitingOn: [ID]
    /// Who moves on, or in the final, who cashes. Empty until every alive
    /// bowler has a score.
    let advancing: [ID]
    /// How many move on (or cash) from this round.
    let keep: Int

    var isComplete: Bool { waitingOn.isEmpty }
}

enum Eliminator {
    static func run<ID: Hashable>(
        entrants: [ID],
        rule: EliminatorRule = EliminatorRule(),
        score: (ID, _ game: Int) -> Int?
    ) -> [EliminatorRound<ID>] {
        var alive = entrants
        var rounds: [EliminatorRound<ID>] = []
        let paying = rule.payingPlaces(entrants: entrants.count)

        for game in 1...rule.games {
            let isFinal = game == rule.games
            let scored = alive.filter { score($0, game) != nil }
            let waiting = alive.filter { score($0, game) == nil }
            let standings = Ranking.rank(scored) { score($0, game) ?? 0 }

            let keep = isFinal ? paying : EliminatorRule.advancing(from: alive.count)
            let advancing = waiting.isEmpty ? standings.filter { $0.place <= keep }.map(\.item) : []

            rounds.append(EliminatorRound(game: game, isFinal: isFinal, standings: standings,
                                          waitingOn: waiting, advancing: advancing, keep: keep))
            guard waiting.isEmpty else { break }
            alive = advancing
        }
        return rounds
    }
}
