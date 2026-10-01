import SwiftUI
import SwiftData

/// Brings a league back from iCloud: on a new phone, or after deleting and
/// reinstalling the app, signed in to the same Apple Account. The league syncs
/// down on its own; this waits for it, shows what's arrived, and says when
/// it's done.
struct RestoreView: View {
    enum Outcome {
        /// Back, including who "This is me" is.
        case restored
        /// The league's back, but nobody was marked "This is me".
        case restoredWithoutMe
        /// Nothing in this iCloud account to restore.
        case nothingFound
        /// Stopped waiting; whatever's left keeps syncing in the background.
        case skipped
    }

    var onFinish: (Outcome) -> Void

    @Environment(SocialService.self) private var social
    @Query private var bowlers: [Bowler]
    @Query private var nights: [Night]
    @Query(filter: #Predicate<Bowler> { $0.isPrimary }) private var primaries: [Bowler]
    @State private var monitor = CloudSyncMonitor.shared
    /// Nil while checking iCloud.
    @State private var hasLeague: Bool?
    @State private var waitedLong = false

    private enum Phase { case checking, noAccount, unavailable, nothing, restoring, restoredMe, restoredLeague }

    private var phase: Phase {
        if social.status == .noAccount { return .noAccount }
        if !BowlingLeagueApp.syncsWithiCloud { return .unavailable }
        if !primaries.isEmpty { return .restoredMe }
        if !bowlers.isEmpty && monitor.importsFinished > 0 && !monitor.isImporting { return .restoredLeague }
        switch hasLeague {
        case nil: return .checking
        case false?: return bowlers.isEmpty ? .nothing : .restoring
        case true?: return .restoring
        }
    }

    var body: some View {
        let phase = phase
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol(phase))
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, isActive: phase == .restoring || phase == .checking)
                .padding(28)
                .glassEffect(in: .circle)
            VStack(spacing: 8) {
                Text(title(phase))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message(phase))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !bowlers.isEmpty || !nights.isEmpty {
                HStack(spacing: 12) {
                    StatTile(title: "Bowlers", value: "\(bowlers.count)", systemImage: "person.3.fill")
                    StatTile(title: "Nights", value: "\(nights.count)", systemImage: "calendar", tint: Theme.secondAccent)
                }
            }
            if phase == .restoring || phase == .checking {
                ProgressView()
            }
            if let error = monitor.lastError, phase == .restoring {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            buttons(phase)
        }
        .padding(24)
        .task {
            hasLeague = await CloudSyncMonitor.iCloudHasLeague()
            // Big leagues with photos can take a while; offer a way on after a minute.
            try? await Task.sleep(for: .seconds(60))
            waitedLong = true
        }
    }

    @ViewBuilder
    private func buttons(_ phase: Phase) -> some View {
        VStack(spacing: 12) {
            switch phase {
            case .restoredMe:
                primary("Continue") { onFinish(.restored) }
            case .restoredLeague:
                primary("Continue") { onFinish(.restoredWithoutMe) }
            case .nothing:
                primary("Set Up as New") { onFinish(.nothingFound) }
            case .noAccount:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) { Text("Open Settings").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                secondary("Not Now") { onFinish(.skipped) }
            case .unavailable:
                secondary("Not Now") { onFinish(.skipped) }
            case .checking, .restoring:
                if waitedLong {
                    secondary("Keep Going in the Background") {
                        onFinish(bowlers.isEmpty ? .skipped : .restoredWithoutMe)
                    }
                }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.glass)
            .controlSize(.large)
    }

    private func symbol(_ phase: Phase) -> String {
        switch phase {
        case .restoredMe, .restoredLeague: "checkmark.icloud"
        case .noAccount, .unavailable: "icloud.slash"
        case .nothing: "icloud"
        case .checking, .restoring: "icloud.and.arrow.down"
        }
    }

    private func title(_ phase: Phase) -> String {
        switch phase {
        case .checking: "Checking iCloud"
        case .restoring: "Restoring Your League"
        case .restoredMe: "Welcome Back\(primaries.first.map { ", \($0.name)" } ?? "")!"
        case .restoredLeague: "Your League Is Back"
        case .nothing: "Nothing to Restore"
        case .noAccount: "Sign In to iCloud"
        case .unavailable: "iCloud Isn't Available"
        }
    }

    private func message(_ phase: Phase) -> String {
        switch phase {
        case .checking:
            "Looking for a league saved to this Apple Account."
        case .restoring:
            waitedLong
                ? "Still bringing everything down. Big leagues with photos can take a few minutes. You can keep going and it'll finish in the background."
                : "Bringing your bowlers, nights and scores down from iCloud. Keep the app open."
        case .restoredMe:
            "Your league, stats and arsenal are back on this phone."
        case .restoredLeague:
            "Your bowlers and nights are back. Next, pick which bowler is you."
        case .nothing:
            "There's no league saved to this Apple Account yet. Set up as new, and from now on it's backed up to iCloud."
        case .noAccount:
            "Sign in with the Apple Account you used before, in Settings › your name. Your league comes back as soon as you do."
        case .unavailable:
            "iCloud couldn't be turned on for this copy of the app, so the league is kept on this phone only."
        }
    }
}
