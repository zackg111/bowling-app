import Foundation

/// Summary of a bowler's watch-measured deliveries.
nonisolated struct MotionStats: Equatable {
    var shots = 0
    var averageSpeedMPH: Double?
    var topSpeedMPH: Double?
    var averageWristRPM: Double?

    init(speeds: [Double], wristRPMs: [Double]) {
        shots = speeds.count
        guard !speeds.isEmpty else { return }
        averageSpeedMPH = speeds.reduce(0, +) / Double(speeds.count)
        topSpeedMPH = speeds.max()
        if !wristRPMs.isEmpty {
            averageWristRPM = wristRPMs.reduce(0, +) / Double(wristRPMs.count)
        }
    }

    /// "16.2" style: mph to one decimal.
    static func mph(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–"
    }

    static func rpm(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–"
    }
}
