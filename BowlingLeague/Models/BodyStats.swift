import Foundation

extension Bowler {
    /// Whole years since their birthday.
    var age: Int? {
        birthday.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }

    /// "34 yrs · 5′ 10″ · 180 lb", from whatever's filled in.
    var bodySummary: String {
        BodyFormat.summary(age: age, heightInches: heightInches, weightPounds: weightPounds)
    }
}

nonisolated enum BodyFormat {
    /// 70 → "5′ 10″"
    static func height(_ inches: Int) -> String {
        "\(inches / 12)′ \(inches % 12)″"
    }

    static func summary(age: Int?, heightInches: Int?, weightPounds: Int?) -> String {
        [age.map { "\($0) yrs" }, heightInches.map(height), weightPounds.map { "\($0) lb" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
