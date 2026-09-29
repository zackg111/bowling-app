import Foundation

nonisolated struct Ranked<Item> {
    let item: Item
    let score: Int
    /// 1-based place; ties share a place (1, 2, 2, 4).
    let place: Int
}

nonisolated enum Ranking {
    static func rank<Item>(_ items: [Item], score: (Item) -> Int) -> [Ranked<Item>] {
        let sorted = items.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }
        var result: [Ranked<Item>] = []
        for (index, (item, value)) in sorted.enumerated() {
            let place = (index > 0 && sorted[index - 1].1 == value) ? result[index - 1].place : index + 1
            result.append(Ranked(item: item, score: value, place: place))
        }
        return result
    }
}
