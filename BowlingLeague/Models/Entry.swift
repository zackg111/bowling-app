import Foundation
import SwiftData

/// A bowler's line for one night: the spreadsheet row.
@Model
final class Entry {
    var bowler: Bowler?
    var night: Night?

    /// Average at the time of the night, so later average changes don't
    /// rewrite old handicaps.
    var average: Int
    var game1: Int?
    var game2: Int?
    var game3: Int?

    /// Doubles team number for this night; partners share a number.
    var doublesTeam: Int?
    var inEliminator: Bool

    init(bowler: Bowler, night: Night, inEliminator: Bool = true) {
        self.bowler = bowler
        self.night = night
        self.average = bowler.average
        self.inEliminator = inEliminator
    }

    var games: [Int?] { [game1, game2, game3] }

    func game(_ number: Int) -> Int? {
        switch number {
        case 1: game1
        case 2: game2
        case 3: game3
        default: nil
        }
    }

    var scratchSeries: Int { games.compactMap { $0 }.reduce(0, +) }

    /// "Total With Handicap" column: scratch series plus the full series
    /// handicap, as in the spreadsheet.
    func totalWithHandicap(_ rule: HandicapRule) -> Int {
        scratchSeries + rule.series(average: average)
    }

    /// Handicapped score for one game, used by the eliminator.
    func handicapped(game number: Int, _ rule: HandicapRule) -> Int? {
        game(number).map { $0 + rule.perGame(average: average) }
    }
}
