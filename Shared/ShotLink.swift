import Foundation
import WatchConnectivity

/// Carries measured shots from the watch to the phone. Uses
/// `transferUserInfo`, which queues and delivers even if the phone app isn't
/// open right now.
nonisolated final class ShotLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = ShotLink()

    /// Called on the main queue on the phone when a shot arrives.
    var onReceive: (@MainActor (ShotMetrics) -> Void)?

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

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["shot"] as? Data,
              let shot = try? JSONDecoder().decode(ShotMetrics.self, from: data) else { return }
        Task { @MainActor in self.onReceive?(shot) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
