import Foundation
import SwiftData

/// Everything in the Saturday Night Special spreadsheet (Doubles&Eliminator
/// and Island tabs), so the app can start with the league as it is today.
enum SeedData {
    struct Row {
        let name: String
        let average: Int
        let games: [Int?]
        let eliminator: Bool
        let island: Bool

        /// On the night's sheet: bowled a game, or entered in the eliminator or Island.
        var bowledTonight: Bool { eliminator || island || games.contains { $0 != nil } }
    }

    /// The night the spreadsheet covers.
    static let nightDate = DateComponents(calendar: .current, year: 2026, month: 9, day: 26).date ?? .now

    static let rows: [Row] = [
        .init(name: "Don Bellen", average: 188, games: [186, nil, nil], eliminator: true, island: false),
        .init(name: "Will Berthiaume", average: 220, games: [205, 231, 259], eliminator: true, island: true),
        .init(name: "Travis Boisclair", average: 198, games: [nil, nil, nil], eliminator: true, island: true),
        .init(name: "Carter Blasko", average: 163, games: [158, nil, nil], eliminator: false, island: false),
        .init(name: "Aaron Chandler", average: 196, games: [nil, nil, nil], eliminator: true, island: true),
        .init(name: "Chris Charron", average: 214, games: [212, nil, nil], eliminator: true, island: true),
        .init(name: "Isaiah Cody", average: 223, games: [nil, nil, nil], eliminator: true, island: false),
        .init(name: "Nick Scott", average: 197, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Mike Bailey", average: 213, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Darren Camp Jr", average: 196, games: [191, nil, nil], eliminator: true, island: true),
        .init(name: "Cameron Hill", average: 218, games: [170, nil, nil], eliminator: true, island: true),
        .init(name: "Dalton Jones", average: 220, games: [nil, nil, nil], eliminator: true, island: false),
        .init(name: "Chris Keyes", average: 164, games: [149, nil, nil], eliminator: true, island: false),
        .init(name: "Alex King", average: 192, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Darren Camp Sr", average: 187, games: [nil, nil, nil], eliminator: true, island: true),
        .init(name: "Brian Lee", average: 169, games: [150, 112, nil], eliminator: true, island: false),
        .init(name: "Shawn Mabb", average: 222, games: [227, nil, nil], eliminator: true, island: true),
        .init(name: "Vernon Marshall", average: 205, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Dan Mitchell", average: 205, games: [171, nil, nil], eliminator: true, island: true),
        .init(name: "Kara Rapp", average: 219, games: [nil, nil, nil], eliminator: true, island: false),
        .init(name: "Phil Rock", average: 210, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Steve Rock", average: 240, games: [255, 259, 201], eliminator: true, island: true),
        .init(name: "Trevor Rose", average: 135, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Paul Rustin", average: 174, games: [140, nil, nil], eliminator: true, island: false),
        .init(name: "Everett Scully", average: 204, games: [nil, nil, nil], eliminator: true, island: true),
        .init(name: "Aiden Stevenson", average: 185, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Colton Weatherwax", average: 209, games: [nil, nil, nil], eliminator: true, island: false),
        .init(name: "Kyle Welch", average: 162, games: [nil, nil, nil], eliminator: true, island: false),
        .init(name: "Dick Wulff", average: 184, games: [215, nil, nil], eliminator: true, island: false),
        .init(name: "Wendy Wulff", average: 144, games: [139, 183, nil], eliminator: true, island: false),
        .init(name: "Brandon Palmateer", average: 228, games: [279, nil, nil], eliminator: true, island: false),
        .init(name: "Nick Buttino", average: 162, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Rich Barry", average: 213, games: [nil, nil, nil], eliminator: false, island: true),
        .init(name: "Royal Donaldson", average: 185, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Shane Germain", average: 228, games: [238, nil, nil], eliminator: true, island: true),
        .init(name: "Dan Welch", average: 120, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Brian Baldwin", average: 162, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Karl DeGrasse", average: 155, games: [178, nil, nil], eliminator: true, island: false),
        .init(name: "Tyler Dalbey", average: 209, games: [258, nil, nil], eliminator: true, island: false),
        .init(name: "Josh Clark", average: 210, games: [nil, nil, nil], eliminator: false, island: false),
        .init(name: "Sean Holcomb", average: 168, games: [122, nil, nil], eliminator: true, island: false),
        .init(name: "Isaac Potter", average: 201, games: [nil, nil, nil], eliminator: false, island: false),
    ]

    /// Loads the spreadsheet the first time the app opens on an empty league.
    /// Only once, so a league someone clears on purpose stays empty.
    @MainActor
    static func loadOnFirstLaunch(into context: ModelContext) {
        let key = "didLoadSpreadsheet"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard (try? context.fetchCount(FetchDescriptor<Bowler>())) == 0 else { return }
        loadSpreadsheet(into: context)
        try? context.save()
    }

    /// Adds every bowler with their average, plus one night holding the
    /// games entered so far, eliminator entrants and Island castaways.
    @MainActor
    static func loadSpreadsheet(into context: ModelContext) {
        let night = Night(title: "Saturday Night Special", date: nightDate)
        context.insert(night)

        for row in rows {
            let bowler = Bowler(name: row.name, average: row.average)
            bowler.onIsland = row.island
            context.insert(bowler)

            guard row.bowledTonight else { continue }
            let entry = Entry(bowler: bowler, night: night, inEliminator: row.eliminator)
            entry.game1 = row.games[0]
            entry.game2 = row.games[1]
            entry.game3 = row.games[2]
            context.insert(entry)
        }
    }
}
