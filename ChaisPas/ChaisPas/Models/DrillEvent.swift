import Foundation
import SwiftData

@Model
final class DrillEvent {
    @Attribute(.unique) var id: UUID
    var sentenceId: String
    var axis: DrillAxis
    var correct: Bool
    var latencyMs: Int
    var pronunciationScore: Double?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        sentenceId: String,
        axis: DrillAxis,
        correct: Bool,
        latencyMs: Int,
        pronunciationScore: Double? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.sentenceId = sentenceId
        self.axis = axis
        self.correct = correct
        self.latencyMs = latencyMs
        self.pronunciationScore = pronunciationScore
        self.timestamp = timestamp
    }
}
