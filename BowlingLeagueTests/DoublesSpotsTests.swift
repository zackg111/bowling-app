import Foundation
import SwiftData
import Testing
@testable import BowlingLeague

/// Doubles spots (including a bowler teamed with themselves) and the
/// automatic switch to bowled average.
@MainActor
struct DoublesSpotsTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let night = Night()

    init() throws {
        container = try ModelContainer(for: Bowler.self, Night.self, Entry.self, Shot.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context.insert(night)
    }

    private func entry(_ name: String, average: Int = 200) -> Entry {
        let bowler = Bowler(name: name, average: average)
        context.insert(bowler)
        let entry = Entry(bowler: bowler, night: night)
        context.insert(entry)
        return entry
    }

    @Test func partnersSeeEachOther() {
        let a = entry("Ann"), b = entry("Bob")
        a.joinTeam(1, partner: b)
        b.joinTeam(1, partner: a)
        #expect(a.partnerNames == ["Bob"])
        #expect(b.partnerNames == ["Ann"])
        #expect(a.openSpots == 0)
    }

    @Test func twoSpotsTwoTeams() {
        let a = entry("Ann"), b = entry("Bob"), c = entry("Cal")
        a.doublesSpots = 2
        a.joinTeam(1, partner: b)
        b.joinTeam(1, partner: a)
        #expect(a.openSpots == 1)
        a.joinTeam(2, partner: c)
        c.joinTeam(2, partner: a)
        #expect(a.teamNumbers == [1, 2])
        #expect(a.partnerNames == ["Bob", "Cal"])
    }

    @Test func teamedWithThemselves() {
        let a = entry("Ann")
        a.doublesSpots = 2
        a.joinTeam(1, partner: a)
        a.joinTeam(1, partner: a)
        #expect(a.teamNumbers == [1, 1])
        #expect(a.openSpots == 0)
        #expect(a.partnerNames == ["Ann"])
        a.leaveTeam(1)
        #expect(a.teamNumbers.isEmpty)
        #expect(a.openSpots == 2)
    }

    @Test func breakingUpKeepsOtherTeams() {
        let a = entry("Ann"), b = entry("Bob"), c = entry("Cal")
        a.doublesSpots = 2
        a.joinTeam(1, partner: b)
        a.joinTeam(2, partner: c)
        a.leaveTeam(1)
        #expect(a.teamNumbers == [2])
        #expect(a.doublesPartnerNames == ["Cal"])
    }

    @Test func nightsPairedBeforeSpotsStillRead() {
        let a = entry("Ann"), b = entry("Bob")
        a.doublesTeam = 3
        a.doublesPartnerName = "Bob"
        b.doublesTeam = 3
        #expect(a.teamNumbers == [3])
        #expect(a.partnerNames == ["Bob"])
        #expect(a.openSpots == 0)
    }

    @Test func switchesToBowledAverageAfterEnoughGames() {
        let a = entry("Ann", average: 180)
        a.game1 = 200
        a.game2 = 210
        a.game3 = 220
        let bowler = a.bowler!
        bowler.followBowledAverage(after: 9)
        #expect(bowler.average == 180)
        bowler.followBowledAverage(after: 3)
        #expect(bowler.average == 210)
        bowler.average = 180
        bowler.followBowledAverage(after: nil)
        #expect(bowler.average == 180)
    }
}
