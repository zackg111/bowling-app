import Foundation

/// One reading from the watch's motion sensors.
nonisolated struct MotionSample: Equatable, Sendable {
    /// Seconds, on the sensor clock.
    let time: TimeInterval
    /// Gyroscope, radians per second, in the watch's frame. On the wrist the
    /// y axis runs along the forearm (12 to 6 o'clock), so rotation about y is
    /// the wrist turning over, and rotation about x and z is the arm swinging.
    let rotationRate: SIMD3<Double>
}

/// What the watch measured for one delivery.
nonisolated struct ShotMetrics: Codable, Equatable, Sendable {
    var date: Date
    /// Hand speed at the bottom of the swing, where the ball comes off.
    /// It's the best estimate of release speed a wrist sensor can give.
    var releaseSpeedMPH: Double
    /// How fast the wrist was turning over at release. More turn means more
    /// hook, so this tracks how much a bowler is "hitting up" on the ball.
    var wristRotationRPM: Double
}

/// Finds deliveries in a stream of watch motion samples.
///
/// A bowling arm swings like a pendulum from the shoulder, so the watch spins
/// about the shoulder at the same rate as the arm. Hand speed is that swing
/// rate times arm length. A delivery shows up as a sharp peak in swing rate;
/// walking and waiting never get close.
nonisolated enum SwingAnalysis {
    static let metersPerSecondToMPH = 2.236_94
    /// Shoulder to palm for an average adult. Settable per bowler on the watch.
    static let defaultArmLength = 0.70
    /// Radians per second. A slow 10 mph delivery with a 0.7 m arm is ~6.4.
    static let minimumSwingRate = 5.5
    /// Seconds between deliveries; nobody throws twice this fast.
    static let minimumGap = 4.0

    static func swingRate(_ sample: MotionSample) -> Double {
        let r = sample.rotationRate
        return (r.x * r.x + r.z * r.z).squareRoot()
    }

    /// Every delivery in `samples` (sorted by time), one per `minimumGap` window.
    static func detectShots(
        in samples: [MotionSample],
        armLength: Double = defaultArmLength,
        startDate: Date = .now,
        startTime: TimeInterval? = nil
    ) -> [(time: TimeInterval, metrics: ShotMetrics)] {
        let origin = startTime ?? samples.first?.time ?? 0
        var peaks: [MotionSample] = []

        for sample in samples where swingRate(sample) >= minimumSwingRate {
            if let last = peaks.last, sample.time - last.time < minimumGap {
                if swingRate(sample) > swingRate(last) { peaks[peaks.count - 1] = sample }
            } else {
                peaks.append(sample)
            }
        }

        return peaks.map { peak in
            let metrics = ShotMetrics(
                date: startDate.addingTimeInterval(peak.time - origin),
                releaseSpeedMPH: swingRate(peak) * armLength * metersPerSecondToMPH,
                wristRotationRPM: abs(peak.rotationRate.y) * 60 / (2 * .pi)
            )
            return (peak.time, metrics)
        }
    }
}
