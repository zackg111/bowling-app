import Foundation

enum PairingMethod: String, CaseIterable, Identifiable {
    /// Random draw.
    case blindDraw
    /// Highest average with lowest average, second highest with second lowest, and so on.
    case highLow

    var id: Self { self }

    var label: String {
        switch self {
        case .blindDraw: "Blind draw"
        case .highLow: "High with low"
        }
    }
}

enum DoublesPairing {
    /// Pairs bowlers into two-person teams. With an odd count, one bowler
    /// is returned as `leftover` for the organizer to place.
    static func pair<Item>(
        _ items: [Item],
        average: (Item) -> Int,
        method: PairingMethod,
        using generator: inout some RandomNumberGenerator
    ) -> (teams: [(Item, Item)], leftover: Item?) {
        var pool: [Item]
        switch method {
        case .blindDraw:
            pool = items.shuffled(using: &generator)
        case .highLow:
            let sorted = items.sorted { average($0) > average($1) }
            pool = []
            var low = sorted.count - 1
            var high = 0
            while high <= low {
                pool.append(sorted[high])
                if high != low { pool.append(sorted[low]) }
                high += 1
                low -= 1
            }
        }

        let leftover = pool.count.isMultiple(of: 2) ? nil : pool.removeLast()
        let teams = stride(from: 0, to: pool.count, by: 2).map { (pool[$0], pool[$0 + 1]) }
        return (teams, leftover)
    }

    static func pair<Item>(
        _ items: [Item],
        average: (Item) -> Int,
        method: PairingMethod
    ) -> (teams: [(Item, Item)], leftover: Item?) {
        var generator = SystemRandomNumberGenerator()
        return pair(items, average: average, method: method, using: &generator)
    }
}
