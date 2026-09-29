import Foundation
import CoreMotion
import HealthKit
import Observation
import WatchKit

/// Runs a bowling workout so the motion sensors stay on, watches the arm swing,
/// and sends every delivery it finds to the phone as soon as it's sure of it.
@Observable
@MainActor
final class ShotTracker {
    enum State: Equatable {
        case idle, starting, tracking
        case failed(String)
    }

    private(set) var state = State.idle
    /// This session's deliveries, oldest first.
    private(set) var shots: [ShotMetrics] = []
    /// False on the simulator and older watches; shots can't be measured then.
    let motionSupported = CMBatchedSensorManager.isDeviceMotionSupported
    /// Meters, shoulder to palm.
    var armLength = SwingAnalysis.defaultArmLength

    var lastShot: ShotMetrics? { shots.last }
    var averageSpeed: Double? {
        shots.isEmpty ? nil : shots.map(\.releaseSpeedMPH).reduce(0, +) / Double(shots.count)
    }
    var topSpeed: Double? { shots.map(\.releaseSpeedMPH).max() }

    /// How much motion history to keep for analysis.
    private static let window: TimeInterval = 8
    /// A peak has to be this old before it counts, so a still-rising swing
    /// isn't reported early.
    private static let settleTime: TimeInterval = 0.5

    private let healthStore = HKHealthStore()
    private let sensors = CMBatchedSensorManager()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var motionTask: Task<Void, Never>?
    private var buffer: [MotionSample] = []
    private var lastEmittedTime: TimeInterval?

    /// Asks for HealthKit access the first time, then starts right away.
    func start() async {
        guard state == .idle || state.isFailure else { return }
        state = .starting
        do {
            try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .bowling
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
            self.session = session
            self.builder = builder
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        buffer = []
        lastEmittedTime = nil
        shots = []
        state = .tracking
        if motionSupported { startMotion() }
    }

    func stop() async {
        motionTask?.cancel()
        motionTask = nil
        sensors.stopDeviceMotionUpdates()
        session?.end()
        if let builder {
            try? await builder.endCollection(at: .now)
            _ = try? await builder.finishWorkout()
        }
        session = nil
        builder = nil
        state = .idle
    }

    private func startMotion() {
        motionTask = Task { [weak self, sensors] in
            do {
                for try await batch in sensors.deviceMotionUpdates() {
                    let samples = batch.map { motion in
                        MotionSample(time: motion.timestamp,
                                     rotationRate: SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z))
                    }
                    self?.process(samples)
                }
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    private func process(_ samples: [MotionSample]) {
        buffer.append(contentsOf: samples)
        guard let newest = buffer.last?.time, let oldest = buffer.first?.time else { return }
        buffer.removeAll { $0.time < newest - Self.window }

        // Sensor timestamps count from boot; line them up with the wall clock.
        let startDate = Date.now.addingTimeInterval(oldest - ProcessInfo.processInfo.systemUptime)
        let found = SwingAnalysis.detectShots(in: buffer, armLength: armLength, startDate: startDate, startTime: oldest)
        for (time, metrics) in found where time <= newest - Self.settleTime {
            if let last = lastEmittedTime, time - last <= SwingAnalysis.minimumGap { continue }
            lastEmittedTime = time
            emit(metrics)
        }
    }

    private func emit(_ shot: ShotMetrics) {
        shots.append(shot)
        WKInterfaceDevice.current().play(.click)
        ShotLink.shared.send(shot)
    }

    #if DEBUG
    /// Sends a made-up delivery so the phone side can be tried without bowling.
    func simulateShot() {
        emit(ShotMetrics(date: .now, releaseSpeedMPH: .random(in: 14...18.5), wristRotationRPM: .random(in: 240...420)))
    }
    #endif
}

extension ShotTracker.State {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}
