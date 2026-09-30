import Testing
@testable import BowlingLeague

/// Numbers come from the Saturday Night Special spreadsheet.
struct HandicapTests {
    let rule = HandicapRule()

    @Test(arguments: [
        (240, 0), (223, 5), (222, 6), (220, 8), (218, 9), (214, 12), (205, 20),
        (198, 25), (196, 27), (188, 33), (174, 44), (163, 53), (162, 54), (135, 76),
    ])
    func perGameMatchesSheet(average: Int, expected: Int) {
        #expect(rule.perGame(average: average) == expected)
    }

    @Test func willsTotalWithHandicap() {
        // Average 220, games 205 / 231 / 259, handicap 24 → 719.
        #expect(205 + 231 + 259 + rule.series(average: 220) == 719)
    }
}

struct DoublesPairingTests {
    @Test func highLowPairsTopWithBottom() {
        let averages = [240, 223, 205, 188, 163, 135]
        let result = DoublesPairing.pair(averages, average: { $0 }, method: .highLow)
        #expect(result.teams.map { [$0.0, $0.1] } == [[240, 135], [223, 163], [205, 188]])
        #expect(result.leftover == nil)
    }

    @Test func oddCountLeavesOneOut() {
        let result = DoublesPairing.pair([1, 2, 3, 4, 5], average: { $0 }, method: .blindDraw)
        #expect(result.teams.count == 2)
        #expect(result.leftover != nil)
    }
}

struct EliminatorTests {
    @Test(arguments: [(25, 14), (22, 12), (20, 10), (14, 8), (13, 8), (8, 4), (7, 4), (4, 2)])
    func halfRoundedUpToEven(field: Int, expected: Int) {
        #expect(EliminatorRule.advancing(from: field) == expected)
    }

    @Test func payingPlacesDependOnField() {
        let rule = EliminatorRule(fourPlacesFrom: 20)
        #expect(rule.payingPlaces(entrants: 19) == 3)
        #expect(rule.payingPlaces(entrants: 20) == 4)
    }

    @Test(arguments: [(10, 5), (9, 5), (14, 7), (12, 6), (6, 3)])
    func intoTheFinalIsPlainHalf(field: Int, expected: Int) {
        #expect(EliminatorRule.advancingToFinal(from: field) == expected)
    }

    @Test func cutsEachGameThenPaysTopThree() {
        // 10 bowlers: 10 → 6 → 3, then top 3 cash.
        let ids = Array(1...10)
        let rounds = Eliminator.run(entrants: ids) { id, game in 100 + id * game }
        #expect(rounds.map(\.keep) == [6, 3, 3])
        #expect(Set(rounds[0].advancing) == Set(5...10))
        #expect(Set(rounds[1].advancing) == Set(8...10))
        #expect(rounds[2].advancing == [10, 9, 8])
    }

    @Test func tenInGameTwoKeepsFive() {
        // 20 bowlers: 20 → 10 → 5, then top 4 cash.
        let ids = Array(1...20)
        let rounds = Eliminator.run(entrants: ids) { id, game in 100 + id * game }
        #expect(rounds.map(\.keep) == [10, 5, 4])
        #expect(Set(rounds[1].advancing) == Set(16...20))
    }

    @Test func tiesAtTheCutAllAdvance() {
        let rounds = Eliminator.run(entrants: ["A", "B", "C", "D", "E"]) { id, _ in id == "E" ? 100 : 200 }
        #expect(rounds[0].keep == 4)
        #expect(Set(rounds[0].advancing) == ["A", "B", "C", "D"])
    }

    @Test func stopsWhileScoresAreMissing() {
        let rounds = Eliminator.run(entrants: ["A", "B"]) { id, _ in id == "A" ? 200 : nil }
        #expect(rounds.count == 1)
        #expect(rounds[0].advancing.isEmpty)
        #expect(rounds[0].waitingOn == ["B"])
    }
}

struct StatsTests {
    @Test func statsAcrossNights() {
        let stats = BowlerStats(nights: [[205, 231, 259], [180, nil, nil]])
        #expect(stats.nightsBowled == 2)
        #expect(stats.gamesBowled == 4)
        #expect(stats.average == 218)
        #expect(stats.highGame == 259)
        #expect(stats.highSeries == 695)
        #expect(stats.games200Plus == 3)
    }
}

struct IslandTests {
    let series = ["A": 700, "B": 620, "C": 540, "S": 650]

    @Test func highWinsImmunityLowIsKickedOff() {
        let night = Island.night(castaways: ["A", "B", "C"]) { series[$0] }
        #expect(night.immunity == ["A"])
        #expect(night.kickedOff == ["C"])
    }

    @Test func lastWeeksImmunityIsSafe() {
        let night = Island.night(castaways: ["A", "B", "C"], protected: ["C"]) { series[$0] }
        #expect(night.kickedOff == ["B"])
    }

    @Test func swimmerOutUnlessHighest() {
        let night = Island.night(castaways: ["A", "B", "C"], swimmers: ["S"]) { series[$0] }
        #expect(night.outForSeason == ["S"])
        #expect(night.backOn.isEmpty)
    }

    @Test func swimmerBowlsHighestAndGetsBackOn() {
        let scores = series.merging(["S": 710]) { $1 }
        let night = Island.night(castaways: ["A", "B", "C"], swimmers: ["S"]) { scores[$0] }
        #expect(night.backOn == ["S"])
        #expect(night.immunity == ["A"])
        #expect(night.kickedOff == ["C"])
    }

    @Test func everyWeekIsAnEliminationByDefault() {
        let round = Island.round(nights: ["n1", "n2"], weeks: 1) { _ in false }
        #expect(round.isElimination)
        #expect(round.window == ["n2"])
    }

    @Test func twoWeekRoundAddsThePreviousNight() {
        let first = Island.round(nights: ["n1"], weeks: 2) { _ in false }
        #expect(!first.isElimination)
        #expect(first.week == 1)

        let second = Island.round(nights: ["n1", "n2"], weeks: 2) { _ in false }
        #expect(second.isElimination)
        #expect(second.window == ["n1", "n2"])
    }

    @Test func roundRestartsAfterARecordedElimination() {
        let round = Island.round(nights: ["n1", "n2", "n3"], weeks: 2) { $0 == "n2" }
        #expect(!round.isElimination)
        #expect(round.window == ["n3"])
    }

    @Test func missedRecordingStillOnlyCountsTheLastWeeks() {
        let round = Island.round(nights: ["n1", "n2", "n3", "n4"], weeks: 3) { _ in false }
        #expect(round.isElimination)
        #expect(round.window == ["n2", "n3", "n4"])
    }

    @Test func waitsForEveryScore() {
        let night = Island.night(castaways: ["A", "B"]) { $0 == "A" ? 700 : nil }
        #expect(!night.isComplete)
        #expect(night.kickedOff.isEmpty)
    }
}
