import Foundation
import SwiftData
import Testing
@testable import BowlingLeague

/// "This is me" and watch shots saving straight into the league database.
@MainActor
struct ShotStorageTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: Bowler.self, Night.self, Entry.self, Shot.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    let shot = ShotMetrics(date: .now, releaseSpeedMPH: 16.2, wristRotationRPM: 300)

    @Test func shotGoesToPrimaryBowler() throws {
        let me = Bowler(name: "Me", average: 200)
        context.insert(me)
        me.makePrimary(in: context)
        Shot.receive(shot, in: context)
        #expect(me.shots.count == 1)
        #expect(me.latestShot?.releaseSpeedMPH == 16.2)
    }

    @Test func onlyOnePrimaryBowler() throws {
        let a = Bowler(name: "A", average: 200), b = Bowler(name: "B", average: 190)
        context.insert(a)
        context.insert(b)
        a.makePrimary(in: context)
        b.makePrimary(in: context)
        #expect(!a.isPrimary)
        #expect(b.isPrimary)
    }

    @Test func unassignedShotsAreAdoptedWhenSomeoneIsMarked() throws {
        Shot.receive(shot, in: context)
        let unassigned = try context.fetch(FetchDescriptor<Shot>(predicate: #Predicate { $0.bowler == nil }))
        #expect(unassigned.count == 1)

        let me = Bowler(name: "Me", average: 200)
        context.insert(me)
        me.makePrimary(in: context)
        #expect(me.shots.count == 1)
    }
}
