import Foundation

/// One item sitting in the MissedIt bank: a sentence that was missed in a drill,
/// with the running count of *consecutive* got-its. Three in a row clears it out;
/// any miss knocks the streak back to zero.
struct MissedItEntry: Codable {
    var sentenceId: String
    var streak: Int
    var addedAt: Date
}

/// The persistent MissedIt bank — everything the user reported "Missed it" on,
/// across Construction / conjugation / vocab / grammar drills, waiting to be
/// typed out correctly three times in a row. Stored in `UserDefaults` (Codable):
/// this is progress state layered over content, not durable content itself, so
/// it stays out of the SwiftData schema.
enum MissedItStore {
    private static let key = "missedit.bank"
    /// Consecutive got-its that clear an item from the bank.
    static let clearStreak = 3

    static func entries() -> [MissedItEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MissedItEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [MissedItEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// A drill item was missed: add it to the bank, or — if it's already there —
    /// reset its streak to zero. Never a duplicate.
    static func capture(sentenceId: String) {
        var all = entries()
        if let i = all.firstIndex(where: { $0.sentenceId == sentenceId }) {
            all[i].streak = 0
        } else {
            all.append(MissedItEntry(sentenceId: sentenceId, streak: 0, addedAt: .now))
        }
        save(all)
    }

    /// Got it inside MissedIt: +1 to the streak, and clear the item once it hits
    /// `clearStreak`. Returns true if the item was cleared out of the bank.
    @discardableResult
    static func markCorrect(sentenceId: String) -> Bool {
        var all = entries()
        guard let i = all.firstIndex(where: { $0.sentenceId == sentenceId }) else { return false }
        all[i].streak += 1
        if all[i].streak >= clearStreak {
            all.remove(at: i)
            save(all)
            return true
        }
        save(all)
        return false
    }

    /// Missed it inside MissedIt: streak back to zero, stays in the bank.
    static func markMissed(sentenceId: String) {
        capture(sentenceId: sentenceId)
    }

    /// The bank's sentence ids, in the order they were added.
    static func ids() -> [String] { entries().map(\.sentenceId) }

    static var count: Int { entries().count }
}
