import SwiftUI

extension EnvironmentValues {
    @Entry var handicapRule = HandicapRule()
    @Entry var eliminatorRule = EliminatorRule()
}

struct RootView: View {
    @AppStorage("handicapBase") private var handicapBase = 230
    @AppStorage("handicapPercent") private var handicapPercent = 80
    @AppStorage("fourPlacesFrom") private var fourPlacesFrom = 20

    var body: some View {
        // iOS / iPadOS 26 tab bar: Liquid Glass on iPhone, and a tab bar that
        // turns into a sidebar on iPad.
        TabView {
            Tab("Home", systemImage: "trophy") {
                NavigationStack { LeaderboardView() }
            }
            Tab("Bowlers", systemImage: "person.3") {
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
    }
}
