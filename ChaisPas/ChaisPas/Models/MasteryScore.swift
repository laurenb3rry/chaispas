import Foundation
import SwiftData

@Model
final class MasteryScore {
    var conceptId: String
    var axis: DrillAxis
    var score: Double
    var updatedAt: Date

    init(conceptId: String, axis: DrillAxis, score: Double = 0, updatedAt: Date = .now) {
        self.conceptId = conceptId
        self.axis = axis
        self.score = score
        self.updatedAt = updatedAt
    }
}
