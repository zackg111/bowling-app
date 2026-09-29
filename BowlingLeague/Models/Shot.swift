import Foundation
import SwiftData

/// One delivery measured by the bowler's Apple Watch.
@Model
final class Shot {
    var date: Date
    var releaseSpeedMPH: Double
    var wristRotationRPM: Double
    /// Nil when a shot arrived before anyone was marked "This is me".
    var bowler: Bowler?

    init(date: Date, releaseSpeedMPH: Double, wristRotationRPM: Double, bowler: Bowler? = nil) {
        self.date = date
        self.releaseSpeedMPH = releaseSpeedMPH
        self.wristRotationRPM = wristRotationRPM
        self.bowler = bowler
    }

    convenience init(_ metrics: ShotMetrics, bowler: Bowler?) {
        self.init(date: metrics.date, releaseSpeedMPH: metrics.releaseSpeedMPH,
                  wristRotationRPM: metrics.wristRotationRPM, bowler: bowler)
    }
}

extension Shot {
    /// Saves a shot from the watch straight away, for whoever is marked
    /// "This is me". With nobody marked it's kept unassigned until someone is.
    static func receive(_ metrics: ShotMetrics, in context: ModelContext) {
        let primary = try? context.fetch(FetchDescriptor<Bowler>(predicate: #Predicate { $0.isPrimary })).first
        context.insert(Shot(metrics, bowler: primary))
        try? context.save()
    }
}

extension Bowler {
    var motionStats: MotionStats {
        MotionStats(speeds: shots.map(\.releaseSpeedMPH), wristRPMs: shots.map(\.wristRotationRPM))
    }

    var latestShot: Shot? { shots.max { $0.date < $1.date } }

    /// Marks this bowler as the phone's owner, clears it on everyone else, and
    /// hands them any watch shots that arrived before anyone was marked.
    func makePrimary(in context: ModelContext) {
        for other in (try? context.fetch(FetchDescriptor<Bowler>(predicate: #Predicate { $0.isPrimary }))) ?? [] {
            other.isPrimary = false
        }
        isPrimary = true
        for shot in (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate { $0.bowler == nil }))) ?? [] {
            shot.bowler = self
        }
    }
}
