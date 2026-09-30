import Foundation

/// One ball: how many pins it knocked down and, when entered on the pin
/// deck, exactly which pins were still standing afterwards.
nonisolated struct Roll: Codable, Hashable, Sendable {
    var count: Int
    /// Pin numbers 1–10 still up after this ball. Nil when only the count was entered.
    var standing: Set<Int>?
}

/// A ball-by-ball scoresheet for one game, scored the standard way:
/// a strike adds the next two balls, a spare the next one, and the 10th
/// frame gets up to three balls.
nonisolated struct GameSheet: Codable, Hashable, Sendable {
    static let allPins: Set<Int> = Set(1...10)
    static let perfectGame = 300

    var rolls: [Roll] = []

    struct Frame: Hashable {
        /// What goes in the little boxes: "X", "/", "-" or a count.
        var marks: [String]
        /// Running total through this frame, once its bonus balls are in.
        var total: Int?
    }

    /// What the next ball faces.
    struct NextBall: Hashable {
        /// 0-based frame, 0–9.
        var frame: Int
        /// Ball within the frame: 0, 1, or 2 in the 10th.
        var ball: Int
        /// How many pins are standing.
        var pinsUp: Int
        /// Which pins are standing. Nil when an earlier ball in this rack was a count only.
        var standing: Set<Int>?
    }

    // MARK: Frames

    /// Balls grouped into frames; the 10th holds up to three.
    private var frameRolls: [[Roll]] {
        var frames: [[Roll]] = []
        var index = 0
        while index < rolls.count && frames.count < 10 {
            if frames.count == 9 {
                frames.append(Array(rolls[index...]))
                break
            }
            let size = rolls[index].count == 10 ? 1 : 2
            frames.append(Array(rolls[index..<min(index + size, rolls.count)]))
            index += size
        }
        return frames
    }

    var frames: [Frame] {
        var result: [Frame] = []
        var running = 0
        var scoring = true
        var index = 0
        for (number, rolls) in frameRolls.enumerated() {
            var score: Int?
            if number < 9 {
                let first = rolls[0].count
                if first == 10 {
                    score = bonus(from: index + 1, balls: 2).map { 10 + $0 }
                } else if rolls.count == 2 {
                    let pins = first + rolls[1].count
                    score = pins == 10 ? bonus(from: index + 2, balls: 1).map { 10 + $0 } : pins
                }
            } else if Self.tenthIsDone(rolls) {
                score = rolls.reduce(0) { $0 + $1.count }
            }
            // A frame waiting on bonus balls holds back every total after it.
            if scoring, let score {
                running += score
                result.append(Frame(marks: Self.marks(for: rolls), total: running))
            } else {
                scoring = false
                result.append(Frame(marks: Self.marks(for: rolls), total: nil))
            }
            index += rolls.count
        }
        return result
    }

    private func bonus(from index: Int, balls: Int) -> Int? {
        guard index + balls <= rolls.count else { return nil }
        return rolls[index..<index + balls].reduce(0) { $0 + $1.count }
    }

    private static func tenthIsDone(_ rolls: [Roll]) -> Bool {
        guard rolls.count >= 2 else { return false }
        return rolls.count == 3 || rolls[0].count + rolls[1].count < 10
    }

    /// Marks for one frame's balls. The rack resets after a strike or spare,
    /// which only matters in the 10th.
    static func marks(for rolls: [Roll]) -> [String] {
        var up = 10
        var fresh = true
        var marks: [String] = []
        for roll in rolls {
            if roll.count == up {
                marks.append(fresh ? "X" : "/")
            } else {
                marks.append(roll.count == 0 ? "-" : "\(roll.count)")
            }
            up -= roll.count
            fresh = false
            if up == 0 {
                up = 10
                fresh = true
            }
        }
        return marks
    }

    // MARK: Progress

    var isComplete: Bool {
        let frames = frameRolls
        return frames.count == 10 && Self.tenthIsDone(frames[9])
    }

    /// Score so far, counting only frames whose bonus balls are in.
    var total: Int {
        frames.last { $0.total != nil }?.total ?? 0
    }

    /// The ball to enter next, or nil once the game is over.
    var next: NextBall? {
        guard !isComplete else { return nil }
        let frames = frameRolls
        guard let last = frames.last else {
            return NextBall(frame: 0, ball: 0, pinsUp: 10, standing: Self.allPins)
        }
        let number = frames.count - 1
        if number < 9 && (last[0].count == 10 || last.count == 2) {
            // That frame is finished; a new one starts on a full rack.
            return NextBall(frame: number + 1, ball: 0, pinsUp: 10, standing: Self.allPins)
        }

        var up = 10
        var standing: Set<Int>? = Self.allPins
        for roll in last {
            up -= roll.count
            standing = roll.standing
            if up == 0 {
                up = 10
                standing = Self.allPins
            }
        }
        return NextBall(frame: number, ball: last.count, pinsUp: up, standing: standing)
    }

    // MARK: Entering balls

    /// Adds a ball. Refuses one that knocks down more pins than are standing,
    /// or any ball once the game is over.
    @discardableResult
    mutating func add(_ roll: Roll) -> Bool {
        guard let next, (0...next.pinsUp).contains(roll.count) else { return false }
        rolls.append(roll)
        return true
    }

    /// Adds a ball knocking down these pins, when the standing pins are known.
    @discardableResult
    mutating func knockDown(_ pins: Set<Int>) -> Bool {
        guard let standing = next?.standing, pins.isSubset(of: standing) else { return false }
        return add(Roll(count: pins.count, standing: standing.subtracting(pins)))
    }

    /// Adds a ball by count only, without saying which pins.
    @discardableResult
    mutating func knockDown(count: Int) -> Bool {
        // All the pins, or none of them, still tells us exactly what's standing.
        guard let next else { return false }
        if next.standing != nil, count == next.pinsUp {
            return add(Roll(count: count, standing: []))
        }
        if let standing = next.standing, count == 0 {
            return add(Roll(count: 0, standing: standing))
        }
        return add(Roll(count: count, standing: nil))
    }

    mutating func undo() {
        if !rolls.isEmpty { rolls.removeLast() }
    }
}
