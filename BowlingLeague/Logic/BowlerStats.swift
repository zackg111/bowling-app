import Foundation

struct BowlerStats: Equatable {
    var nightsBowled = 0
    var gamesBowled = 0
    var totalPins = 0
    var highGame = 0
    var highSeries = 0
    var games200Plus = 0

    /// Scratch average across every game bowled, rounded down like most leagues.
    var average: Int? { gamesBowled > 0 ? totalPins / gamesBowled : nil }

    init(nights: [[Int?]]) {
        for night in nights {
            let games = night.compactMap { $0 }
            guard !games.isEmpty else { continue }
            nightsBowled += 1
            gamesBowled += games.count
            totalPins += games.reduce(0, +)
            highGame = max(highGame, games.max() ?? 0)
            highSeries = max(highSeries, games.reduce(0, +))
            games200Plus += games.filter { $0 >= 200 }.count
        }
    }
}
