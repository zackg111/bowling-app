import SwiftUI
import SwiftData

extension EnvironmentValues {
    @Entry var handicapRule = HandicapRule()
    @Entry var eliminatorRule = EliminatorRule()
    /// Games after which a bowler's league average switches to their bowled
    /// average. Nil when that's turned off in Settings.
    @Entry var bowledAverageAfter: Int? = 9
}

struct RootView: View {
    @AppStorage("handicapBase") private var handicapBase = 230
    @AppStorage("handicapPercent") private var handicapPercent = 80
    @AppStorage("fourPlacesFrom") private var fourPlacesFrom = 20
    @AppStorage("useBowledAverage") private var useBowledAverage = true
    @AppStorage("bowledAverageGames") private var bowledAverageGames = 9
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var social = SocialService.shared
    /// Setup has been finished or skipped once on this device.
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var onboarding = false
    /// This iCloud account already has a league: setup starts by restoring it.
    @State private var restoreFirst = false

    private var bowledAverageAfter: Int? { useBowledAverage ? bowledAverageGames : nil }

    var body: some View {
        // iOS / iPadOS 26 tab bar: Liquid Glass on iPhone, and a tab bar that
        // turns into a sidebar on iPad.
        TabView {
            Tab("Home", systemImage: "trophy") {
                NavigationStack { LeaderboardView() }
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                NavigationStack { ProfileView() }
            }
            Tab("Bowlers", systemImage: "figure.bowling") {
                NavigationStack { BowlersView() }
            }
            Tab("Nights", systemImage: "calendar") {
                NavigationStack { NightsView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
            Tab(role: .search) {
                NavigationStack { BowlerSearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .environment(\.handicapRule, HandicapRule(base: handicapBase, percent: handicapPercent))
        .environment(\.eliminatorRule, EliminatorRule(fourPlacesFrom: fourPlacesFrom))
        .environment(\.bowledAverageAfter, bowledAverageAfter)
        .environment(social)
        // Find your iCloud account and profile, then share any games that
        // changed. Again whenever the app comes back or goes away.
        .task {
            await social.refresh()
            // First launch: set up who you are, unless that's already done
            // (you're marked "This is me" and have a profile).
            if !didOnboard {
                let hasMe = ((try? context.fetchCount(FetchDescriptor<Bowler>(predicate: #Predicate { $0.isPrimary }))) ?? 0) > 0
                if hasMe && social.status == .ready {
                    didOnboard = true
                } else {
                    // A reinstall or new phone on the same Apple Account: bring the
                    // league back first instead of starting over.
                    if !hasMe && social.status != .noAccount {
                        restoreFirst = await CloudSyncMonitor.iCloudHasLeague() || social.me != nil
                    }
                    onboarding = true
                }
            }
            await social.shareLeague(from: context)
        }
        .fullScreenCover(isPresented: $onboarding) {
            OnboardingView(restoring: restoreFirst) { didOnboard = true }
                .environment(social)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .inactive else { return }
            Task { await social.shareLeague(from: context) }
        }
        // On launch and whenever the setting changes, bring everyone who has
        // bowled enough games onto their bowled average.
        .task(id: bowledAverageAfter) {
            for bowler in (try? context.fetch(FetchDescriptor<Bowler>())) ?? [] {
                bowler.followBowledAverage(after: bowledAverageAfter)
            }
        }
    }
}
