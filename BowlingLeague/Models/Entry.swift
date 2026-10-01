import Foundation
import SwiftData

/// A bowler's line for one night: the spreadsheet row.
@Model
final class Entry {
    var bowler: Bowler?
    var night: Night?

    /// Average at the time of the night, so later average changes don't
    /// rewrite old handicaps.
    var average = 0
    var game1: Int?
    var game2: Int?
    var game3: Int?

    /// How many doubles spots they have tonight: 0 sits out, 2 bowls on two teams.
    var doublesSpots = 1
    /// Team number for each paired spot. Someone drawn with themselves has
    /// the same number twice.
    var doublesTeamNumbers: [Int] = []
    /// Partner's name for each paired spot, saved at pairing (same order as the
    /// team numbers), so history still shows who they doubled with if the
    /// partner later leaves the night.
    var doublesPartnerNames: [String] = []
    /// Nights paired before bowlers could have more than one spot kept a
    /// single team and partner here. Read through `teamNumbers`.
    var doublesTeam: Int?
    var doublesPartnerName: String?
    var inEliminator = true
    /// Not bowling tonight. The Island counts a blind score for them; their
    /// games stay empty, so averages, stats and every other game skip them.
    var isAbsent = false
    /// In-game mode's ball-by-ball sheets for games 1–3, as JSON.
    var sheetsData: Data?
    /// The ball used for each game, by name ("" for none), so history keeps
    /// the name if the ball is later deleted.
    var gameBalls: [String] = []

    init(bowler: Bowler, night: Night, inEliminator: Bool = true) {
        self.bowler = bowler
        self.night = night
        self.average = bowler.average
        self.inEliminator = inEliminator
    }

    var games: [Int?] { [game1, game2, game3] }

    // MARK: Doubles

    /// Team numbers of their paired spots.
    var teamNumbers: [Int] {
        doublesTeamNumbers.isEmpty ? (doublesTeam.map { [$0] } ?? []) : doublesTeamNumbers
    }

    private var savedPartnerNames: [String] {
        doublesTeamNumbers.isEmpty ? (doublesPartnerName.map { [$0] } ?? []) : doublesPartnerNames
    }

    /// Spots still waiting for a partner.
    var openSpots: Int { max(0, doublesSpots - teamNumbers.count) }

    /// Puts one of their spots on a team. Called once per spot, so a bowler
    /// teamed with themselves is called twice.
    func joinTeam(_ number: Int, partner: Entry) {
        let numbers = teamNumbers + [number]
        let names = savedPartnerNames + [partner.bowler?.name ?? ""]
        doublesTeamNumbers = numbers
        doublesPartnerNames = names
        doublesTeam = nil
        doublesPartnerName = nil
    }

    /// Takes their spots off this team.
    func leaveTeam(_ number: Int) {
        let names = savedPartnerNames
        let kept = teamNumbers.indices.filter { teamNumbers[$0] != number }
        doublesPartnerNames = kept.map { names.indices.contains($0) ? names[$0] : "" }
        doublesTeamNumbers = kept.map { teamNumbers[$0] }
        doublesTeam = nil
        doublesPartnerName = nil
    }

    func leaveAllTeams() {
        doublesTeamNumbers = []
        doublesPartnerNames = []
        doublesTeam = nil
        doublesPartnerName = nil
    }

    /// Who they doubled with, one per spot: the partner still on the night,
    /// or the name saved at pairing. Their own name when teamed with themselves.
    var partnerNames: [String] {
        let saved = savedPartnerNames
        let numbers = teamNumbers
        return numbers.indices.compactMap { index in
            let number = numbers[index]
            if numbers.filter({ $0 == number }).count > 1 {
                // Teamed with themselves: list them once.
                return numbers.firstIndex(of: number) == index ? bowler?.name : nil
            }
            let partner = night?.entries?.first {
                $0.persistentModelID != persistentModelID && $0.teamNumbers.contains(number)
            }
            let name = partner?.bowler?.name ?? (saved.indices.contains(index) ? saved[index] : "")
            return name.isEmpty ? nil : name
        }
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

    /// The ball used for game 1, 2 or 3.
    func ball(for number: Int) -> String? {
        let name = gameBalls.indices.contains(number - 1) ? gameBalls[number - 1] : ""
        return name.isEmpty ? nil : name
    }

    /// Sets the ball for all three games.
    func setBall(_ name: String?) {
        gameBalls = name.map { Array(repeating: $0, count: 3) } ?? []
    }

    /// What an absent bowler is credited with for each game on the Island:
    /// their average minus 10 pins.
    var blindScore: Int { max(0, average - 10) }

    /// The three games the Island counts: the blind score when absent.
    var islandGames: [Int?] { isAbsent ? Array(repeating: blindScore, count: 3) : games }

    /// The Island's handicapped series for this night. Zero when nothing was bowled.
    func islandSeries(_ rule: HandicapRule) -> Int {
        let played = islandGames.compactMap { $0 }
        return played.isEmpty ? 0 : played.reduce(0, +) + rule.series(average: average)
    }

    /// Marks them absent (or back), stepping them out of the doubles and
    /// eliminator while they are away, since they have no scores for those.
    func setAbsent(_ absent: Bool) {
        guard absent != isAbsent else { return }
        isAbsent = absent
        if absent {
            for number in Set(teamNumbers) {
                for entry in night?.entries ?? [] where entry.teamNumbers.contains(number) {
                    entry.leaveTeam(number)
                }
            }
            doublesSpots = 0
            inEliminator = false
        } else {
            doublesSpots = 1
            inEliminator = true
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
