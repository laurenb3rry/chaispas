import Foundation
import SwiftData

@Model
final class SessionLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationSec: Int
    var itemsCompleted: Int
    var newConceptId: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        durationSec: Int = 0,
        itemsCompleted: Int = 0,
        newConceptId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.durationSec = durationSec
        self.itemsCompleted = itemsCompleted
        self.newConceptId = newConceptId
    }
}
