import Foundation
import Testing
@testable import BowlingLeague

/// Synthetic watch samples: quiet arm, one or more swing peaks.
struct SwingAnalysisTests {
    /// 50 Hz samples from `start` to `end`, quiet except for `peaks` (time, swing rad/s, wrist rad/s).
    func samples(from start: Double = 0, to end: Double, peaks: [(Double, Double, Double)]) -> [MotionSample] {
        stride(from: start, through: end, by: 0.02).map { t in
            let t = (t * 100).rounded() / 100
            if let peak = peaks.first(where: { abs($0.0 - t) < 0.001 }) {
                return MotionSample(time: t, rotationRate: SIMD3(peak.1, peak.2, 0))
            }
            return MotionSample(time: t, rotationRate: SIMD3(0.5, 0.1, 0.3))
        }
    }

    @Test func singlePeakGivesReleaseSpeed() {
        let shots = SwingAnalysis.detectShots(in: samples(to: 6, peaks: [(3, 8, 0)]), armLength: 0.7)
        #expect(shots.count == 1)
        #expect(abs(shots[0].metrics.releaseSpeedMPH - 8 * 0.7 * 2.23694) < 0.001)
        #expect(abs(shots[0].metrics.releaseSpeedMPH - 12.53) < 0.01)
        #expect(shots[0].time == 3)
    }

    @Test func peaksCloserThanGapCountOnceKeepingHigher() {
        let shots = SwingAnalysis.detectShots(in: samples(to: 10, peaks: [(2, 7, 0), (4.5, 9, 0)]))
        #expect(shots.count == 1)
        #expect(shots[0].time == 4.5)
        #expect(abs(shots[0].metrics.releaseSpeedMPH - 9 * SwingAnalysis.defaultArmLength * 2.23694) < 0.001)
    }

    @Test func peaksFarApartAreSeparateShots() {
        let shots = SwingAnalysis.detectShots(in: samples(to: 14, peaks: [(2, 7, 0), (8, 9, 0)]))
        #expect(shots.map(\.time) == [2, 8])
    }

    @Test func slowSwingIsNotAShot() {
        #expect(SwingAnalysis.detectShots(in: samples(to: 6, peaks: [(3, 5.4, 0)])).isEmpty)
    }

    @Test func wristRPMFromYRotation() {
        let shots = SwingAnalysis.detectShots(in: samples(to: 6, peaks: [(3, 8, -30)]))
        #expect(shots.count == 1)
        #expect(abs(shots[0].metrics.wristRotationRPM - 30 * 60 / (2 * .pi)) < 0.001)
    }

    @Test func motionStatsSummarizesShots() {
        let stats = MotionStats(speeds: [14, 16, 18], wristRPMs: [300, 330])
        #expect(stats.shots == 3)
        #expect(stats.averageSpeedMPH == 16)
        #expect(stats.topSpeedMPH == 18)
        #expect(stats.averageWristRPM == 315)
        #expect(MotionStats.mph(16.24) == "16.2")
        #expect(MotionStats(speeds: [], wristRPMs: []).averageSpeedMPH == nil)
    }
}
