import Foundation
import SwiftData

/// A Listen episode (PLAN2 §3.5/§4). Transcript lines and comprehension
/// questions are codable payloads decoded by the player at runtime.
@Model
final class ListenEpisode {
    @Attribute(.unique) var id: String
    var title: String
    var level: String            // A–D
    var topic: String
    var speakerLabels: [String]  // display names; transcript lines carry 1/2
    var durationSec: Int         // estimated, fast rendition
    var audioFullFast: String    // full-episode files in listen/audio/
    var audioFullSlow: String
    var transcriptData: Data
    var questionsData: Data
    var completedCount: Int = 0
    // Best question run so far (correct answers out of `questions.count`);
    // nil until the first completion
    var bestScore: Int?

    init(
        id: String,
        title: String,
        level: String,
        topic: String,
        speakerLabels: [String],
        durationSec: Int,
        audioFullFast: String,
        audioFullSlow: String,
        transcriptData: Data,
        questionsData: Data,
        completedCount: Int = 0,
        bestScore: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.level = level
        self.topic = topic
        self.speakerLabels = speakerLabels
        self.durationSec = durationSec
        self.audioFullFast = audioFullFast
        self.audioFullSlow = audioFullSlow
        self.transcriptData = transcriptData
        self.questionsData = questionsData
        self.completedCount = completedCount
        self.bestScore = bestScore
    }

    func decodedTranscript() throws -> [TranscriptLine] {
        try JSONDecoder().decode([TranscriptLine].self, from: transcriptData)
    }

    func decodedQuestions() throws -> [ComprehensionQuestion] {
        try JSONDecoder().decode([ComprehensionQuestion].self, from: questionsData)
    }
}
