import Foundation
import WatchConnectivity

/// One game scored on the watch. Sent after every ball with the whole sheet,
/// so the phone always ends up with the latest (Undo included).
nonisolated struct WatchGame: Codable, Equatable, Sendable {
    /// When scoring started on the watch that night, so the phone files the
    /// game under the right night.
    var night: Date
    /// Game 1, 2 or 3.
    var game: Int
    var sheet: GameSheet
}

/// Carries measured shots and scored games from the watch to the phone. Uses
/// `transferUserInfo`, which queues and delivers in order even if the phone
/// app isn't open right now.
nonisolated final class ShotLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = ShotLink()

    /// Called on the main queue on the phone when a shot arrives.
    var onReceive: (@MainActor (ShotMetrics) -> Void)?
    /// Called on the main queue on the phone when a scored game arrives.
    var onReceiveGame: (@MainActor (WatchGame) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ shot: ShotMetrics) {
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(shot) else { return }
        WCSession.default.transferUserInfo(["shot": data])
    }

    func send(_ game: WatchGame) {
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(game) else { return }
        WCSession.default.transferUserInfo(["game": data])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["shot"] as? Data,
           let shot = try? JSONDecoder().decode(ShotMetrics.self, from: data) {
            Task { @MainActor in self.onReceive?(shot) }
        }
        if let data = userInfo["game"] as? Data,
           let game = try? JSONDecoder().decode(WatchGame.self, from: data) {
            Task { @MainActor in self.onReceiveGame?(game) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
