import Foundation
import Testing
@testable import BowlingLeague

/// The Profile tab's stats, filters, tiers and monthly rankings.
struct GameStatsTests {
    private func sheet(_ counts: [Int]) -> GameSheet {
        var sheet = GameSheet()
        for count in counts { sheet.knockDown(count: count) }
        return sheet
    }

    private func game(_ sheet: GameSheet, date: Date = .now, center: String = "", ball: String? = nil) -> BowledGame {
        BowledGame(seriesID: "x", date: date, number: 1, score: sheet.total, sheet: sheet, center: center, ball: ball)
    }

    @Test func splits() {
        #expect(PinRack.isSplit([7, 10]))
        #expect(PinRack.isSplit([4, 6]))
        #expect(PinRack.isSplit([3, 10]))
        #expect(PinRack.isSplit([5, 7]))
        #expect(!PinRack.isSplit([2, 8]))      // one behind the other
        #expect(!PinRack.isSplit([3, 6, 10]))  // connected
        #expect(!PinRack.isSplit([1, 7]))      // headpin still up
        #expect(!PinRack.isSplit([10]))
    }

    @Test func perfectGameIsAllStrikes() {
        let stats = GameStats(games: [game(sheet(Array(repeating: 10, count: 12)))])
        #expect(stats.strikeRate == 1)
        #expect(stats.firstBalls == 12)
        #expect(stats.cleanRate == 1)
        #expect(stats.strikeAfterStrikeRate == 1)
        #expect(stats.spareRate == nil)
        #expect(stats.firstBallAverage == 10)
    }

    @Test func sparesAndOpens() {
        // Nine spares (9 then 1), then an open tenth (9, 0).
        let stats = GameStats(games: [game(sheet(Array(repeating: [9, 1], count: 9).flatMap { $0 } + [9, 0]))])
        #expect(stats.strikes == 0)
        #expect(stats.spareChances == 10)
        #expect(stats.spares == 9)
        #expect(stats.singlePinChances == 10)
        #expect(stats.cleanFrames == 9)
        #expect(stats.frames == 10)
    }

    @Test func leavesNeedThePins() {
        var game = GameSheet()
        // First frame: leave the 7-10, miss both. Then strikes out.
        game.knockDown(Set(1...10).subtracting([7, 10]))
        game.knockDown(count: 0)
        for _ in 0..<11 { game.knockDown(count: 10) }
        let stats = GameStats(games: [self.game(game)])
        #expect(stats.splits == 1)
        #expect(stats.commonLeaves.first?.id == "7-10")
        #expect(stats.commonLeaves.first?.count == GameStats.LeaveCount(left: 1, converted: 0))
    }

    @Test func unfinishedSheetsOnlyCountTheScore() {
        let stats = GameStats(games: [game(sheet([10, 10]))])
        #expect(stats.games == 1)
        #expect(!stats.hasSheets)
    }

    @Test func tiers() {
        #expect(AverageTier(average: 222).low == 221)
        #expect(AverageTier(average: 230).high == 230)
        #expect(AverageTier(average: 231).low == 231)
        #expect(AverageTier(average: 222).next.low == 231)
    }

    @Test func filterKeepsTheLastGames() {
        let day: TimeInterval = 86_400
        let series = (0..<20).map { index in
            BowledSeries(profileID: "me", date: Date(timeIntervalSince1970: Double(index) * day),
                         center: index.isMultiple(of: 2) ? "Kingpin" : "Sunset", scores: [100 + index, nil, nil])
        }
        let last5 = StatsFilter(span: .lastGames(5)).games(from: series)
        #expect(last5.map(\.score) == [115, 116, 117, 118, 119])
        let kingpin = StatsFilter(center: "Kingpin", span: .lastGames(100)).games(from: series)
        #expect(kingpin.count == 10)
    }

    @Test func monthlyMetrics() {
        let calendar = Calendar(identifier: .gregorian)
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        let series = [
            BowledSeries(profileID: "me", date: september, scores: [200, 210, 220]),
            BowledSeries(profileID: "me", date: september.addingTimeInterval(86_400), scores: [250, nil, nil]),
            BowledSeries(profileID: "me", date: october, scores: [300, 300, 300]),
        ]
        let metrics = LeaderMetrics(series: series, month: september, calendar: calendar)
        #expect(metrics?.highGame == 250)
        #expect(metrics?.bestBlock == 630)
        #expect(metrics?.endurance == 4)
        #expect(metrics?.average == 220)
        #expect(LeaderMetrics(series: series, month: calendar.date(from: DateComponents(year: 2026, month: 8))!, calendar: calendar) == nil)
    }

    @Test func mergeKeepsLocalCopies() {
        let date = Date(timeIntervalSince1970: 1000)
        let local = [BowledSeries(profileID: "me", date: date, scores: [200, nil, nil])]
        let shared = [BowledSeries(profileID: "me", date: date, scores: [150, nil, nil]),
                      BowledSeries(profileID: "me", date: date.addingTimeInterval(60), scores: [180, nil, nil])]
        #expect(BowledSeries.merge(local, shared).map { $0.scores[0] } == [200, 180])
    }
}
