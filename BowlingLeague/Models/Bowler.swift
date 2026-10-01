import Foundation
import SwiftData

@Model
final class Bowler {
    // Every stored property has a default and every relationship is optional:
    // iCloud sync (CloudKit) requires both.
    var name = ""
    /// The average the league uses for handicap. Entered by hand to start;
    /// `BowlerStats` can suggest one from bowled games.
    var average = 0
    var createdAt = Date.now
    /// Profile photo, downscaled JPEG. Stored outside the database file.
    @Attribute(.externalStorage) var photoData: Data?
    /// False once the bowler has left the league. Their history and stats stay.
    var isActive = true
    /// The person using this phone ("This is me"). At most one bowler.
    var isPrimary = false
    /// The friend's own account (their iCloud user ID for this app), once
    /// they're linked. Their games here are shared to it once they approve.
    var profileID: String?

    /// Island (the season-long survivor game).
    var onIsland = false
    var hasImmunity = false
    /// Kicked off last week; gets back on by bowling the highest series this week.
    var islandSwimming = false
    /// Off the island for the rest of the season.
    var islandOutDate: Date?

    var isIslandCastaway: Bool { onIsland && !islandSwimming && islandOutDate == nil }
    var isIslandSwimmer: Bool { onIsland && islandSwimming && islandOutDate == nil }

    @Relationship(deleteRule: .cascade, inverse: \Entry.bowler)
    var entries: [Entry]? = []

    /// Deliveries measured by this bowler's Apple Watch.
    @Relationship(deleteRule: .cascade, inverse: \Shot.bowler)
    var shots: [Shot]? = []

    /// Their arsenal.
    @Relationship(deleteRule: .cascade, inverse: \Ball.bowler)
    var balls: [Ball]? = []

    init(name: String, average: Int) {
        self.name = name
        self.average = average
        self.createdAt = .now
    }

    var stats: BowlerStats {
        BowlerStats(nights: (entries ?? []).map(\.games))
    }

    /// Once they've bowled `minimumGames` games, their league average follows
    /// their bowled average (the setting in Settings; nil when it's off).
    /// Nights already bowled keep the average they were bowled with.
    func followBowledAverage(after minimumGames: Int?) {
        guard let minimumGames else { return }
        let stats = self.stats
        guard stats.gamesBowled >= minimumGames, let bowled = stats.average, bowled != average else { return }
        average = bowled
    }
}
