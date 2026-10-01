import CloudKit

/// A bowler's own account as friends see it, kept in the app's public iCloud
/// database. Anyone can read it; only its owner can change it.
struct PublicProfile: Identifiable, Hashable, Sendable {
    /// The owner's iCloud user ID for this app.
    let id: String
    var name = ""
    /// Home bowling center.
    var center = ""
    var average = 0
    /// Small JPEG.
    var photo: Data?
    /// Who they follow.
    var following: [String] = []
    /// Friends they've allowed to share league nights they scored for them.
    var trustedScorers: [String] = []

    static let recordType = "Profile"

    /// User IDs look like the public database's own Users records, so profiles get a prefix.
    static func recordID(for userID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile-\(userID)")
    }

    init(id: String) {
        self.id = id
    }

    /// Nil unless the record was made by the account it says it belongs to,
    /// so nobody can stand in for someone else's profile.
    init?(record: CKRecord, myID: String?) {
        guard record.recordType == Self.recordType,
              let owner = record["owner"] as? String,
              record.creatorID(myID: myID) == owner else { return nil }
        id = owner
        name = record["name"] as? String ?? ""
        center = record["center"] as? String ?? ""
        average = record["average"] as? Int ?? 0
        photo = record["photo"] as? Data
        following = record["following"] as? [String] ?? []
        trustedScorers = record["trustedScorers"] as? [String] ?? []
    }

    func write(to record: CKRecord) {
        record["owner"] = id
        record["name"] = name
        // Lowercased copies are what search and "my center" match on.
        record["nameKey"] = name.lowercased()
        record["center"] = center
        record["centerKey"] = center.lowercased()
        record["average"] = average
        record["photo"] = photo
        record["following"] = following
        record["trustedScorers"] = trustedScorers
    }
}

/// Someone who added this account's owner to their league and wants to share
/// the nights they score for them.
struct LinkRequest: Identifiable, Hashable, Sendable {
    static let recordType = "LinkRequest"

    let id: String
    /// Who sent it, from iCloud itself rather than anything in the record.
    let scorerID: String
    var scorerName: String
    /// What they call you in their league.
    var bowlerName: String
}

extension CKRecord {
    /// The account that created this record. CloudKit reports your own
    /// records with a placeholder name, so that's swapped for your real ID.
    func creatorID(myID: String?) -> String? {
        guard let name = creatorUserRecordID?.recordName else { return nil }
        return name == CKCurrentUserDefaultName ? myID : name
    }
}
