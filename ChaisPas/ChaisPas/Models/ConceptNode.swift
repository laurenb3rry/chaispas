import Foundation
import SwiftData

@Model
final class ConceptNode {
    @Attribute(.unique) var id: String
    var type: ConceptType
    var tier: Int
    var prereqIds: [String]
    var title: String
    var explanationText: String
    var examples: [CanonicalExample]
    var streetMapping: String
    var introduced: Bool

    init(
        id: String,
        type: ConceptType,
        tier: Int,
        prereqIds: [String],
        title: String,
        explanationText: String,
        examples: [CanonicalExample],
        streetMapping: String,
        introduced: Bool = false
    ) {
        self.id = id
        self.type = type
        self.tier = tier
        self.prereqIds = prereqIds
        self.title = title
        self.explanationText = explanationText
        self.examples = examples
        self.streetMapping = streetMapping
        self.introduced = introduced
    }
}
