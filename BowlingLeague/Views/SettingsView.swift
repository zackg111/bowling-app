import SwiftUI

struct SettingsView: View {
    @AppStorage("handicapBase") private var handicapBase = 230
    @AppStorage("handicapPercent") private var handicapPercent = 80
    @AppStorage("fourPlacesFrom") private var fourPlacesFrom = 20
    @AppStorage("useBowledAverage") private var useBowledAverage = true
    @AppStorage("bowledAverageGames") private var bowledAverageGames = 9
    @AppStorage("islandWeeks") private var islandWeeks = 1
    @Environment(SocialService.self) private var social
    @State private var sync = CloudSyncMonitor.shared
    @State private var restoring = false
    @State private var settingsRestored = false

    var body: some View {
        Form {
            Section {
                Stepper("Base: \(handicapBase)", value: $handicapBase, in: 150...300)
                Stepper("Percent: \(handicapPercent)%", value: $handicapPercent, in: 0...100, step: 5)
            } header: {
                Text("Handicap")
            } footer: {
                let rule = HandicapRule(base: handicapBase, percent: handicapPercent)
                Text("\(handicapPercent)% of (\(handicapBase) − average) per game. A 190 average gets \(rule.perGame(average: 190)) a game, \(rule.series(average: 190)) a series.")
            }

            Section {
                Toggle("Use bowled average", isOn: $useBowledAverage)
                if useBowledAverage {
                    Stepper("After \(bowledAverageGames) games", value: $bowledAverageGames, in: 1...60)
                }
            } header: {
                Text("Average")
            } footer: {
                Text(useBowledAverage
                     ? "Once a bowler has bowled \(bowledAverageGames) games, their average switches to their bowled average and keeps updating as they bowl. Nights already bowled keep their handicap."
                     : "Averages only change when you edit them.")
            }

            Section {
                Stepper("Pay 4 places from \(fourPlacesFrom) bowlers", value: $fourPlacesFrom, in: 4...60)
            } header: {
                Text("Eliminator")
            } footer: {
                Text("Half the field, rounded up to an even number, moves on after game 1. After game 2 it's plain half (10 bowlers → 5). Smaller nights pay 3 places.")
            }

            Section {
                Stepper(islandWeeks == 1 ? "Every week" : "Every \(islandWeeks) weeks", value: $islandWeeks, in: 1...12)
            } header: {
                Text("Island")
            } footer: {
                Text(islandWeeks == 1
                     ? "Someone goes swimming after every night."
                     : "Someone goes swimming every \(islandWeeks) weeks. Scores add up tonight and the \(islandWeeks - 1) \(islandWeeks == 2 ? "night" : "nights") before it.")
            }

            Section {
                LabeledContent("Status") {
                    if !BowlingLeagueApp.syncsWithiCloud || social.status == .noAccount {
                        Label("Off", systemImage: "icloud.slash")
                    } else if sync.isImporting {
                        Label("Syncing…", systemImage: "arrow.clockwise.icloud")
                    } else {
                        Label("On", systemImage: "checkmark.icloud")
                    }
                }
                if let last = sync.lastSynced {
                    LabeledContent("Last synced") {
                        Text(last, format: .relative(presentation: .named))
                    }
                }
                if let error = sync.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button("Restore League from iCloud", systemImage: "icloud.and.arrow.down") { restoring = true }
                Button(settingsRestored ? "Settings Restored" : "Restore Settings from iCloud",
                       systemImage: settingsRestored ? "checkmark" : "slider.horizontal.3") {
                    SettingsSync.pull(overwrite: true)
                    settingsRestored = true
                }
                .disabled(!SettingsSync.hasSavedSettings || settingsRestored)
            } header: {
                Text("iCloud")
            } footer: {
                Text(social.status == .noAccount
                     ? "Sign in to iCloud in the Settings app to back up your league and bring it back on a new phone."
                     : "Your league and settings are backed up to your Apple Account. On a new phone, or after reinstalling, sign in with the same account and they come back on their own. Restore shows the progress.")
            }
        }
        .laneBackground()
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $restoring) {
            NavigationStack {
                RestoreView { _ in restoring = false }
                    .laneBackground()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { restoring = false } }
                    }
            }
        }
    }
}
