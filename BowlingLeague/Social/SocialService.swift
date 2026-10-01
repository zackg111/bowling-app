import CloudKit
import CryptoKit
import Observation
import SwiftData

/// Friends, through the app's public iCloud database. Everyone keeps their own
/// Apple Account and their own private league; what's public is a profile,
/// who you follow, and the games you choose to share.
///
/// Record types (each creator owns their records; everyone signed in can read):
/// - `Profile` (`profile-<user ID>`): name, center, average, photo, following, trusted scorers.
/// - `Series` (`series-<profile ID>-<time>`): one night's games for one bowler.
///   Posted by the bowler, or by a friend scoring them in a league; a friend's
///   only count once the bowler trusts them.
/// - `LinkRequest` (`link-<scorer>-<profile ID>`): "I added you to my league".
@Observable
final class SocialService {
    static let shared = SocialService()

    enum Status: Equatable {
        case checking
        /// Not signed in to iCloud, or iCloud is restricted.
        case noAccount
        case failed(String)
        /// Signed in, but no profile made yet.
        case needsProfile
        case ready
    }

    enum SocialError: LocalizedError {
        case noProfile
        var errorDescription: String? { "Set up your profile first." }
    }

    private(set) var status: Status = .checking
    /// Your iCloud user ID for this app.
    private(set) var myID: String?
    private(set) var me: PublicProfile?
    private(set) var following: [PublicProfile] = []
    private(set) var followers: [PublicProfile] = []
    /// People asking to share league nights they scored for you.
    private(set) var requests: [LinkRequest] = []
    /// People you've let share league nights for you.
    private(set) var scorers: [PublicProfile] = []

    @ObservationIgnored private var myRecord: CKRecord?
    @ObservationIgnored private var seriesCache: [String: [SharedSeries]] = [:]
    @ObservationIgnored private let container = CKContainer(identifier: BowlingLeagueApp.cloudContainer)
    private var database: CKDatabase { container.publicCloudDatabase }

    private struct SharedSeries {
        let scorerID: String
        let series: BowledSeries
    }

    // MARK: Account

    /// Finds the iCloud account and its profile, then who it's connected to.
    func refresh() async {
        do {
            guard try await container.accountStatus() == .available else {
                status = .noAccount
                return
            }
            let userID = try await container.userRecordID().recordName
            myID = userID
            if let record = try await fetch(PublicProfile.recordID(for: userID)),
               let profile = PublicProfile(record: record, myID: userID) {
                myRecord = record
                me = profile
                status = .ready
                await loadConnections()
            } else {
                status = .needsProfile
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Makes or updates your profile from your bowler: name, center, photo,
    /// average, and age, height and weight if you show them.
    func saveProfile(from bowler: Bowler) async throws {
        guard let myID else { throw SocialError.noProfile }
        var profile = me ?? PublicProfile(id: myID)
        profile.name = bowler.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.photo = bowler.photoData.flatMap { AvatarPicker.downscaled($0, maxSide: 256) }
        apply(bowler, to: &profile)
        try await save(profile)
        if status != .ready {
            status = .ready
            await loadConnections()
        }
    }

    /// Keeps your profile in step with your bowler (a new average, a
    /// birthday passing, an edit on another device) without re-sending the photo.
    func syncProfile(from bowler: Bowler) async {
        guard var profile = me else { return }
        let before = profile
        apply(bowler, to: &profile)
        guard profile != before else { return }
        try? await save(profile)
    }

    private func apply(_ bowler: Bowler, to profile: inout PublicProfile) {
        profile.center = bowler.homeCenter.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.average = bowler.average
        let shares = bowler.sharesBodyStats
        profile.age = shares ? bowler.age : nil
        profile.heightInches = shares ? bowler.heightInches : nil
        profile.weightPounds = shares ? bowler.weightPounds : nil
    }

    private func save(_ profile: PublicProfile) async throws {
        guard let myID else { throw SocialError.noProfile }
        let record = myRecord ?? CKRecord(recordType: PublicProfile.recordType, recordID: PublicProfile.recordID(for: myID))
        profile.write(to: record)
        do {
            myRecord = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Changed from another device since: apply this on top of that.
            guard let server = error.serverRecord else { throw error }
            profile.write(to: server)
            myRecord = try await database.save(server)
        }
        me = profile
    }

    // MARK: Friends

    func loadConnections() async {
        guard let me, let myID else { return }
        if let profiles = try? await profiles(ids: me.following) { following = profiles }
        if let profiles = try? await profiles(ids: me.trustedScorers) { scorers = profiles }
        if let records = try? await query(PublicProfile.recordType, NSPredicate(format: "following CONTAINS %@", myID)) {
            followers = Self.byName(records.compactMap { PublicProfile(record: $0, myID: myID) })
        }
        if let records = try? await query(LinkRequest.recordType, NSPredicate(format: "profileID == %@", myID)) {
            let declined = Set(UserDefaults.standard.stringArray(forKey: declinedKey) ?? [])
            requests = records.compactMap { record in
                guard let scorer = record.creatorID(myID: myID), scorer != myID,
                      !me.trustedScorers.contains(scorer), !declined.contains(record.recordID.recordName) else { return nil }
                return LinkRequest(id: record.recordID.recordName, scorerID: scorer,
                                   scorerName: record["scorerName"] as? String ?? "",
                                   bowlerName: record["bowlerName"] as? String ?? "")
            }
        }
    }

    func isFollowing(_ profile: PublicProfile) -> Bool {
        me?.following.contains(profile.id) ?? false
    }

    func follow(_ profile: PublicProfile) async throws {
        guard var me else { throw SocialError.noProfile }
        guard profile.id != me.id, !me.following.contains(profile.id) else { return }
        me.following.append(profile.id)
        try await save(me)
        following = Self.byName(following + [profile])
    }

    func unfollow(_ profile: PublicProfile) async throws {
        guard var me else { throw SocialError.noProfile }
        me.following.removeAll { $0 == profile.id }
        try await save(me)
        following.removeAll { $0.id == profile.id }
    }

    /// Bowlers whose name starts with this, e.g. "bill" or "bill b".
    func search(_ text: String) async throws -> [PublicProfile] {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count >= 2 else { return [] }
        let records = try await query(PublicProfile.recordType, NSPredicate(format: "nameKey BEGINSWITH %@", key), limit: 50)
        return Self.byName(records.compactMap { PublicProfile(record: $0, myID: myID) }.filter { $0.id != myID })
    }

    /// Everyone in the app whose name or home center starts with this, names first.
    func searchEveryone(_ text: String) async throws -> [PublicProfile] {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count >= 2 else { return [] }
        async let byName = search(key)
        async let atCenter = query(PublicProfile.recordType, NSPredicate(format: "centerKey BEGINSWITH %@", key), limit: 50)
        let names = try await byName
        let centers = try await atCenter.compactMap { PublicProfile(record: $0, myID: myID) }
            .filter { profile in profile.id != myID && !names.contains { $0.id == profile.id } }
        return names + Self.byName(centers)
    }

    /// Everyone whose home center is yours.
    func centerProfiles() async throws -> [PublicProfile] {
        guard let me, !me.center.isEmpty else { return [] }
        let records = try await query(PublicProfile.recordType, NSPredicate(format: "centerKey == %@", me.center.lowercased()), limit: 100)
        return records.compactMap { PublicProfile(record: $0, myID: myID) }.filter { $0.id != myID }
    }

    func profile(id: String) async throws -> PublicProfile? {
        try await fetch(PublicProfile.recordID(for: id)).flatMap { PublicProfile(record: $0, myID: myID) }
    }

    private func profiles(ids: [String]) async throws -> [PublicProfile] {
        guard !ids.isEmpty else { return [] }
        let results = try await database.records(for: ids.map { PublicProfile.recordID(for: $0) })
        return Self.byName(results.values.compactMap { try? $0.get() }.compactMap { PublicProfile(record: $0, myID: myID) })
    }

    // MARK: League links

    /// Asks a friend to let your league share the nights you score for them.
    func requestLink(to profile: PublicProfile, bowlerName: String) async throws {
        guard let myID, let me else { throw SocialError.noProfile }
        let record = CKRecord(recordType: LinkRequest.recordType, recordID: CKRecord.ID(recordName: "link-\(myID)-\(profile.id)"))
        record["profileID"] = profile.id
        record["scorerName"] = me.name
        record["bowlerName"] = bowlerName
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    func approve(_ request: LinkRequest) async throws {
        guard var me else { throw SocialError.noProfile }
        if !me.trustedScorers.contains(request.scorerID) { me.trustedScorers.append(request.scorerID) }
        try await save(me)
        requests.removeAll { $0.id == request.id }
        seriesCache[me.id] = nil
        if let scorer = try? await profile(id: request.scorerID) { scorers = Self.byName(scorers + [scorer]) }
    }

    func decline(_ request: LinkRequest) {
        var declined = UserDefaults.standard.stringArray(forKey: declinedKey) ?? []
        declined.append(request.id)
        UserDefaults.standard.set(declined, forKey: declinedKey)
        requests.removeAll { $0.id == request.id }
    }

    /// Stops counting nights this friend scored for you.
    func revoke(_ scorer: PublicProfile) async throws {
        guard var me else { throw SocialError.noProfile }
        me.trustedScorers.removeAll { $0 == scorer.id }
        try await save(me)
        scorers.removeAll { $0.id == scorer.id }
        seriesCache[me.id] = nil
    }

    private var declinedKey: String { "declinedLinkRequests-\(myID ?? "")" }

    // MARK: Games

    /// Someone's shared games: their own, and the league nights scored by friends they trust.
    func series(for profile: PublicProfile, refresh: Bool = false) async throws -> [BowledSeries] {
        try await shared(for: profile, refresh: refresh).map(\.series)
    }

    /// Your games: the ones on this device, plus league nights friends you
    /// trust scored for you.
    func mySeries(_ bowler: Bowler, refresh: Bool = false) async -> [BowledSeries] {
        let local = bowler.bowledSeries(as: myID ?? "local")
        guard let me, let remote = try? await shared(for: me, refresh: refresh) else { return local }
        // This device is the say on your own games, even before it re-shares them.
        return BowledSeries.merge(local, remote.filter { $0.scorerID != me.id }.map(\.series))
    }

    private func shared(for profile: PublicProfile, refresh: Bool) async throws -> [SharedSeries] {
        if !refresh, let cached = seriesCache[profile.id] { return cached }
        let records = try await query("Series", NSPredicate(format: "profileID == %@", profile.id), limit: 2000)
        let trusted = Set(profile.trustedScorers + [profile.id])
        let decoder = JSONDecoder()
        let series = records.compactMap { record -> SharedSeries? in
            guard let scorer = record.creatorID(myID: myID), trusted.contains(scorer),
                  let data = record["payload"] as? Data,
                  let series = try? decoder.decode(BowledSeries.self, from: data),
                  series.profileID == profile.id else { return nil }
            return SharedSeries(scorerID: scorer, series: series)
        }
        .sorted { $0.series.date < $1.series.date }
        seriesCache[profile.id] = series
        return series
    }

    /// Shares the games of everyone in this league who has an account: you,
    /// and friends linked to theirs. Only what changed since last time is sent,
    /// and nights since deleted (or a friend unlinked) are taken down.
    func shareLeague(from context: ModelContext) async {
        guard status == .ready, let myID else { return }
        let bowlers = (try? context.fetch(FetchDescriptor<Bowler>())) ?? []
        var series: [BowledSeries] = []
        for bowler in bowlers {
            guard let owner = bowler.isPrimary ? myID : bowler.profileID else { continue }
            series += bowler.bowledSeries(as: owner)
        }
        if let primary = bowlers.first(where: \.isPrimary) {
            // Profiles made before the center lived on your bowler kept it only here.
            if primary.homeCenter.isEmpty, let center = me?.center, !center.isEmpty { primary.homeCenter = center }
            await syncProfile(from: primary)
        }

        let ledgerKey = "sharedSeries-\(myID)"
        var ledger = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        var current: [String: (series: BowledSeries, hash: String)] = [:]
        for item in series {
            let hash = SHA256.hash(data: Data(item.fingerprint.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            current["series-\(item.id)"] = (item, hash)
        }

        let encoder = JSONEncoder()
        let toSave = current.filter { ledger[$0.key] != $0.value.hash }.compactMap { name, item -> CKRecord? in
            guard let payload = try? encoder.encode(item.series) else { return nil }
            let record = CKRecord(recordType: "Series", recordID: CKRecord.ID(recordName: name))
            record["profileID"] = item.series.profileID
            record["date"] = item.series.date
            record["payload"] = payload
            return record
        }
        let toDelete = ledger.keys.filter { current[$0] == nil }.map { CKRecord.ID(recordName: $0) }
        guard !toSave.isEmpty || !toDelete.isEmpty else { return }

        // CloudKit takes up to 400 changes at a time.
        for start in stride(from: 0, to: max(toSave.count, toDelete.count), by: 200) {
            let saving = Array(toSave.dropFirst(start).prefix(200))
            let deleting = Array(toDelete.dropFirst(start).prefix(200))
            guard let outcome = try? await database.modifyRecords(saving: saving, deleting: deleting,
                                                                 savePolicy: .allKeys, atomically: false) else { continue }
            for (id, result) in outcome.saveResults {
                // A night someone else already shared for this bowler fails here, which is fine: it's only shared once.
                if case .success = result { ledger[id.recordName] = current[id.recordName]?.hash }
            }
            for (id, result) in outcome.deleteResults {
                if case .success = result { ledger[id.recordName] = nil }
                if case .failure(let error as CKError) = result, error.code == .unknownItem { ledger[id.recordName] = nil }
            }
        }
        UserDefaults.standard.set(ledger, forKey: ledgerKey)
        seriesCache[myID] = nil
    }

    // MARK: CloudKit

    private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func query(_ type: String, _ predicate: NSPredicate, limit: Int = 400) async throws -> [CKRecord] {
        var (results, cursor) = try await database.records(matching: CKQuery(recordType: type, predicate: predicate), resultsLimit: 200)
        var records = results.compactMap { try? $0.1.get() }
        while let next = cursor, records.count < limit {
            (results, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: 200)
            records += results.compactMap { try? $0.1.get() }
        }
        return records
    }

    private static func byName(_ profiles: [PublicProfile]) -> [PublicProfile] {
        profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
