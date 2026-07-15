import Foundation
import SwiftData

/// A Speak scenario (PLAN2 §3.4/§4). The branching dialogue variants stay a
/// codable JSON payload — branch trees don't fit relational modeling cleanly,
/// and the player parses them at runtime via `decodedVariants()`.
@Model
final class Scenario {
    @Attribute(.unique) var id: String
    var title: String
    var icon: String
    var settingBlurb: String
    var difficulty: Int
    var variantsData: Data
    var completedCount: Int = 0
    var lastPlayed: Date?

    init(
        id: String,
        title: String,
        icon: String,
        settingBlurb: String,
        difficulty: Int,
        variantsData: Data,
        completedCount: Int = 0,
        lastPlayed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.settingBlurb = settingBlurb
        self.difficulty = difficulty
        self.variantsData = variantsData
        self.completedCount = completedCount
        self.lastPlayed = lastPlayed
    }

    func decodedVariants() throws -> [ScenarioVariant] {
        try JSONDecoder().decode([ScenarioVariant].self, from: variantsData)
    }
}
