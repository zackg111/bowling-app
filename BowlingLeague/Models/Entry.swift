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
    /// Partner's name when teams were paired, so history still shows who
    /// they doubled with if the partner later leaves the night.
    var doublesPartnerName: String?
    var inEliminator: Bool
    /// In-game mode's ball-by-ball sheets for games 1–3, as JSON.
    var sheetsData: Data?

    init(bowler: Bowler, night: Night, inEliminator: Bool = true) {
        self.bowler = bowler
        self.night = night
        self.average = bowler.average
        self.inEliminator = inEliminator
    }

    var games: [Int?] { [game1, game2, game3] }

    /// This night's doubles partner, while they're still on the night.
    var doublesPartner: Entry? {
        guard let doublesTeam else { return nil }
        return night?.entries.first { $0.doublesTeam == doublesTeam && $0.persistentModelID != persistentModelID }
    }

    /// Who they doubled with: the partner on the night, or the name saved at pairing.
    var partnerName: String? {
        doublesPartner?.bowler?.name ?? doublesPartnerName
    }

    func game(_ number: Int) -> Int? {
        switch number {
        case 1: game1
        case 2: game2
        case 3: game3
        default: nil
        }
    }

    /// Sets game 1, 2 or 3.
    func setGame(_ number: Int, to score: Int?) {
        switch number {
        case 1: game1 = score
        case 2: game2 = score
        case 3: game3 = score
        default: break
        }
    }

    /// The ball-by-ball sheet for game 1, 2 or 3 (empty until in-game mode is used).
    func sheet(_ number: Int) -> GameSheet {
        let sheets = sheetsData.flatMap { try? JSONDecoder().decode([GameSheet].self, from: $0) } ?? []
        return sheets.indices.contains(number - 1) ? sheets[number - 1] : GameSheet()
    }

    /// Saves a game's sheet. A finished sheet becomes that game's score; undoing
    /// back from finished clears the score again.
    func setSheet(_ sheet: GameSheet, for number: Int) {
        var sheets = (1...3).map { self.sheet($0) }
        let wasComplete = sheets[number - 1].isComplete
        sheets[number - 1] = sheet
        sheetsData = try? JSONEncoder().encode(sheets)
        if sheet.isComplete {
            setGame(number, to: sheet.total)
        } else if wasComplete {
            setGame(number, to: nil)
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
