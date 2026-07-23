import Foundation

/// A resumable snapshot of an in-progress drill run, so leaving a unit's drill
/// part-way through and coming back picks up on the same prompt rather than
/// restarting. Kept deliberately light (just what the adaptive ladder needs to
/// rebuild its position) and stored in `UserDefaults` — this is ephemeral resume
/// state, not durable content, so it stays out of the SwiftData schema.
struct DrillRunSnapshot: Codable {
    /// The sentence ids shown so far, in the order they appeared. The last is
    /// the frontier the user was on.
    var shownIds: [String]
    var rung: Int
    var ladderStreak: Int
    var itemsCompleted: Int
    var gradedCount: Int
    var correctCount: Int
    var startedAt: Date
}

/// Per-unit persistence for `DrillRunSnapshot`, keyed by concept id.
enum DrillRunStore {
    private static func key(_ unitId: String) -> String { "drillrun.snapshot.\(unitId)" }

    static func save(unitId: String, snapshot: DrillRunSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key(unitId))
    }

    static func load(unitId: String) -> DrillRunSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(unitId)) else { return nil }
        return try? JSONDecoder().decode(DrillRunSnapshot.self, from: data)
    }

    static func clear(unitId: String) {
        UserDefaults.standard.removeObject(forKey: key(unitId))
    }

    /// Whether an unfinished run is waiting to be resumed for this unit.
    static func hasProgress(_ unitId: String) -> Bool {
        guard let snap = load(unitId: unitId) else { return false }
        return !snap.shownIds.isEmpty
    }
}
