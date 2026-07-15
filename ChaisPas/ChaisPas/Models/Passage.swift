import Foundation
import SwiftData

/// A Read passage (PLAN2 §3.6/§4). Text-only in v2 (no audio). The gloss map
/// and questions are codable payloads decoded by the Reader at runtime.
@Model
final class Passage {
    @Attribute(.unique) var id: String
    var title: String
    var style: String            // news / review / texto / ... (10 styles)
    var tier: Int                // 0–3, aligned with concept-graph tiers
    var topic: String
    var body: String
    var wordCount: Int
    var glossData: Data          // {surface form: english gloss}
    var questionsData: Data
    var read: Bool = false
    // Correct answers out of `questions.count` on the last read; nil if unread
    var lastScore: Int?

    init(
        id: String,
        title: String,
        style: String,
        tier: Int,
        topic: String,
        body: String,
        wordCount: Int,
        glossData: Data,
        questionsData: Data,
        read: Bool = false,
        lastScore: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.style = style
        self.tier = tier
        self.topic = topic
        self.body = body
        self.wordCount = wordCount
        self.glossData = glossData
        self.questionsData = questionsData
        self.read = read
        self.lastScore = lastScore
    }

    func decodedGloss() throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: glossData)
    }

    func decodedQuestions() throws -> [ComprehensionQuestion] {
        try JSONDecoder().decode([ComprehensionQuestion].self, from: questionsData)
    }
}
