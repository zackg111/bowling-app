import Foundation
import SwiftData

/// One night of bowling (e.g. a Saturday Night Special): who bowled,
/// their three games, the doubles teams, the eliminator and the Island.
@Model
final class Night {
    // Defaults on everything and an optional relationship, for iCloud sync.
    var title = "Saturday Night Special"
    var date = Date.now
    /// Where it was bowled, e.g. the bowling alley. Empty when not set.
    var location = ""
    /// Set once this night's Island result has been applied to the bowlers.
    var islandRecorded = false

    @Relationship(deleteRule: .cascade, inverse: \Entry.night)
    var entries: [Entry]? = []

    init(title: String = "Saturday Night Special", date: Date = .now) {
        self.title = title
        self.date = date
    }

    /// Opens the location in Apple Maps.
    var mapsURL: URL? {
        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }

    var sortedEntries: [Entry] {
        (entries ?? []).sorted { ($0.bowler?.name ?? "") < ($1.bowler?.name ?? "") }
    }
}
