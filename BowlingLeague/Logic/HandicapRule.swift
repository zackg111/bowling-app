import Foundation

/// Handicap per game = 80% of (230 − average), rounded down, never negative.
/// Matches every row of the Saturday Night Special sheet
/// (e.g. average 223 → 5 a game, 15 a series; average 240 → 0).
struct HandicapRule: Equatable {
    var base: Int = 230
    var percent: Int = 80

    func perGame(average: Int) -> Int {
        max(0, (base - average) * percent / 100)
    }

    func series(average: Int, games: Int = 3) -> Int {
        perGame(average: average) * games
    }
}
