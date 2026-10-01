import Foundation

/// The ten pins of a rack, for naming leaves and spotting splits.
nonisolated enum PinRack {
    /// Where each pin stands: across in half pin-spacings, and rows back from the headpin.
    private static let spots: [Int: (x: Int, row: Int)] = [
        1: (0, 0), 2: (-1, 1), 3: (1, 1), 4: (-2, 2), 5: (0, 2), 6: (2, 2),
        7: (-3, 3), 8: (-1, 3), 9: (1, 3), 10: (3, 3),
    ]

    /// Back row first, the way a rack is drawn from the approach.
    static let rows: [[Int]] = [[7, 8, 9, 10], [4, 5, 6], [2, 3], [1]]

    /// Two pins one ball can take out together: side by side, on a diagonal,
    /// or one straight behind the other (1-5, 2-8, 3-9).
    static func touching(_ a: Int, _ b: Int) -> Bool {
        guard let p = spots[a], let q = spots[b] else { return false }
        let across = abs(p.x - q.x), back = abs(p.row - q.row)
        return (back == 0 && across == 2) || (back == 1 && across == 1) || (back == 2 && across == 0)
    }

    /// A split: the headpin is down and what's left stands in two or more
    /// groups with a gap between them (7-10, 4-6, 3-10, 5-7).
    static func isSplit(_ standing: Set<Int>) -> Bool {
        guard standing.count >= 2, !standing.contains(1), let start = standing.min() else { return false }
        var reached: Set<Int> = [start]
        var queue = [start]
        while let pin = queue.popLast() {
            for other in standing where !reached.contains(other) && touching(pin, other) {
                reached.insert(other)
                queue.append(other)
            }
        }
        return reached.count < standing.count
    }

    /// How a leave is written: "7-10", "10", "2-4-5-8".
    static func name(_ pins: Set<Int>) -> String {
        pins.sorted().map(String.init).joined(separator: "-")
    }
}

/// The stats page's numbers for a set of games. Scores come from every game;
/// the first-ball, spare and leave numbers only from finished ball-by-ball sheets.
nonisolated struct GameStats: Equatable, Sendable {
    struct LeaveCount: Equatable, Sendable {
        var left = 0
        var converted = 0
        var rate: Double { left > 0 ? Double(converted) / Double(left) : 0 }
    }

    /// Every game's score, in the order given.
    var scores: [Int] = []
    /// Games with a finished ball-by-ball sheet.
    var sheetGames = 0
    /// Balls thrown at a full rack.
    var firstBalls = 0
    var firstBallPins = 0
    var strikes = 0
    var splits = 0
    /// First balls thrown right after a strike, and how many of them struck too.
    var afterStrike = 0
    var strikesAfterStrike = 0
    var spareChances = 0
    var spares = 0
    var singlePinChances = 0
    var singlePinSpares = 0
    var frames = 0
    /// Frames with a strike or a spare.
    var cleanFrames = 0
    /// What the first ball left, when the pins were entered on the pin deck.
    var leaves: [Set<Int>: LeaveCount] = [:]

    init(games: [BowledGame]) {
        for game in games {
            scores.append(game.score)
            if let sheet = game.sheet, sheet.isComplete { add(sheet) }
        }
    }

    private mutating func add(_ sheet: GameSheet) {
        sheetGames += 1
        for frame in sheet.frames {
            frames += 1
            if frame.marks.first == "X" || (frame.marks.count > 1 && frame.marks[1] == "/") {
                cleanFrames += 1
            }
        }

        var up = 10
        var firstOfRack = true
        var lastFirstStruck = false
        var leave: Set<Int>?
        for roll in sheet.rolls {
            if firstOfRack {
                firstBalls += 1
                firstBallPins += roll.count
                if lastFirstStruck { afterStrike += 1 }
                if roll.count == 10 {
                    strikes += 1
                    if lastFirstStruck { strikesAfterStrike += 1 }
                    lastFirstStruck = true
                    continue // a fresh rack again
                }
                lastFirstStruck = false
                leave = roll.standing
                if let standing = roll.standing, PinRack.isSplit(standing) { splits += 1 }
                up = 10 - roll.count
                firstOfRack = false
            } else {
                // The second ball at a rack always ends it: a spare, an open
                // frame, or (open in the 10th) the game.
                spareChances += 1
                let converted = roll.count == up
                if converted { spares += 1 }
                if up == 1 {
                    singlePinChances += 1
                    if converted { singlePinSpares += 1 }
                }
                if let leave, !leave.isEmpty {
                    leaves[leave, default: LeaveCount()].left += 1
                    if converted { leaves[leave, default: LeaveCount()].converted += 1 }
                }
                firstOfRack = true
                leave = nil
            }
        }
    }

    var games: Int { scores.count }
    /// Rounded down, like a league average.
    var average: Int? { scores.isEmpty ? nil : scores.reduce(0, +) / scores.count }
    var highGame: Int? { scores.max() }
    var games200Plus: Int { scores.filter { $0 >= 200 }.count }
    var hasSheets: Bool { sheetGames > 0 }

    var firstBallAverage: Double? { firstBalls > 0 ? Double(firstBallPins) / Double(firstBalls) : nil }
    var strikeRate: Double? { Self.rate(strikes, firstBalls) }
    var splitRate: Double? { Self.rate(splits, firstBalls) }
    /// First balls that left a spare that isn't a split.
    var leaveRate: Double? { Self.rate(firstBalls - strikes - splits, firstBalls) }
    var spareRate: Double? { Self.rate(spares, spareChances) }
    var singlePinRate: Double? { Self.rate(singlePinSpares, singlePinChances) }
    var cleanRate: Double? { Self.rate(cleanFrames, frames) }
    var strikeAfterStrikeRate: Double? { Self.rate(strikesAfterStrike, afterStrike) }

    struct LeaveTally: Identifiable, Equatable, Sendable {
        let pins: Set<Int>
        let count: LeaveCount
        var id: String { PinRack.name(pins) }
    }

    /// Leaves seen most often first.
    var commonLeaves: [LeaveTally] {
        leaves.map { LeaveTally(pins: $0.key, count: $0.value) }
            .sorted { ($0.count.left, $1.id) > ($1.count.left, $0.id) }
    }

    private static func rate(_ part: Int, _ whole: Int) -> Double? {
        whole > 0 ? Double(part) / Double(whole) : nil
    }
}

/// Averages in bands of ten: 221–230, 231–240.
nonisolated struct AverageTier: Equatable, Sendable {
    let low: Int
    var high: Int { low + 9 }

    init(average: Int) {
        low = max(0, average - 1) / 10 * 10 + 1
    }

    var next: AverageTier { AverageTier(average: high + 1) }

    /// How far into this band an average is, 0.1 to 1.
    func progress(_ average: Int) -> Double {
        Double(min(max(average - low + 1, 0), 10)) / 10
    }
}
