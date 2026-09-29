import Testing
@testable import BowlingLeague

/// Ball-by-ball scoring for in-game mode.
struct GameSheetTests {
    private func sheet(_ counts: [Int]) -> GameSheet {
        var sheet = GameSheet()
        for count in counts { sheet.knockDown(count: count) }
        return sheet
    }

    @Test func perfectGame() {
        let game = sheet(Array(repeating: 10, count: 12))
        #expect(game.isComplete)
        #expect(game.total == 300)
        #expect(game.frames[9].marks == ["X", "X", "X"])
    }

    @Test func allSpares() {
        let game = sheet(Array(repeating: 5, count: 21))
        #expect(game.isComplete)
        #expect(game.total == 150)
        #expect(game.frames[0].marks == ["5", "/"])
    }

    @Test func gutterGame() {
        let game = sheet(Array(repeating: 0, count: 20))
        #expect(game.isComplete)
        #expect(game.total == 0)
        #expect(game.frames[0].marks == ["-", "-"])
    }

    @Test func openTenthEndsAfterTwoBalls() {
        let game = sheet(Array(repeating: 9, count: 10).flatMap { [$0, 0] })
        #expect(game.isComplete)
        #expect(game.total == 90)
        #expect(!sheet(Array(repeating: 0, count: 19)).isComplete)
    }

    @Test func strikeWaitsForTwoMoreBalls() {
        var game = sheet([10])
        #expect(game.frames[0].total == nil)
        game.knockDown(count: 3)
        #expect(game.frames[0].total == nil)
        game.knockDown(count: 4)
        #expect(game.frames[0].total == 17)
        #expect(game.frames[1].total == 24)
    }

    @Test func spareInTenthGetsOneMoreBall() {
        var game = sheet(Array(repeating: 0, count: 18) + [7, 3])
        #expect(!game.isComplete)
        #expect(game.next?.pinsUp == 10)
        game.knockDown(count: 10)
        #expect(game.isComplete)
        #expect(game.total == 20)
        #expect(game.frames[9].marks == ["7", "/", "X"])
    }

    @Test func refusesMorePinsThanStanding() {
        var game = sheet([7])
        #expect(game.next?.pinsUp == 3)
        #expect(!game.knockDown(count: 4))
        #expect(game.rolls.count == 1)
    }

    @Test func noBallsAfterTheGameEnds() {
        var game = sheet(Array(repeating: 0, count: 20))
        #expect(!game.knockDown(count: 0))
        #expect(game.next == nil)
    }

    @Test func pinDeckTracksWhatsStanding() {
        var game = GameSheet()
        #expect(game.knockDown([1, 2, 3, 5, 8, 9]))
        #expect(game.next?.standing == [4, 6, 7, 10])
        #expect(game.next?.pinsUp == 4)
        // Can't knock down a pin that's already down.
        #expect(!game.knockDown([1]))
        #expect(game.knockDown([4, 6, 7, 10]))
        #expect(game.frames[0].marks == ["6", "/"])
        #expect(game.next?.standing == GameSheet.allPins)
    }

    @Test func countOnlyBallLeavesPinsUnknown() {
        var game = GameSheet()
        game.knockDown(count: 8)
        #expect(game.next?.standing == nil)
        #expect(game.next?.pinsUp == 2)
    }

    @Test func undoRemovesLastBall() {
        var game = sheet([10, 10, 10])
        game.undo()
        #expect(game.rolls.count == 2)
        #expect(game.frames[0].total == nil)
    }
}
