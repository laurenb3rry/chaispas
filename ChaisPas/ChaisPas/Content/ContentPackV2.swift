import Foundation

// MARK: - Shared codable payloads
//
// These round-trip: decoded from the pack JSON at import, re-encoded into the
// SwiftData models' Data blobs, decoded again by the mode players at runtime.
// Coding keys therefore mirror the pack's snake_case exactly.

struct ScenarioVariant: Codable, Hashable {
    var variantId: String
    var nodes: [ScenarioNode]

    enum CodingKeys: String, CodingKey {
        case nodes
        case variantId = "variant_id"
    }
}

struct ScenarioNode: Codable, Hashable {
    var nodeId: String
    var speaker: String            // "npc" | "user"
    var english: String
    var frenchStreet: String
    var frenchFormal: String?      // user lines; npc only when meaningfully different
    var audioRefs: [String: String]?  // npc: street_fast/street_slow; user adds formal
    var next: String?              // nil = end of path (when branches is nil too)
    var branches: [ScenarioBranch]?

    enum CodingKeys: String, CodingKey {
        case speaker, english, next, branches
        case nodeId = "node_id"
        case frenchStreet = "french_street"
        case frenchFormal = "french_formal"
        case audioRefs = "audio_refs"
    }
}

struct ScenarioBranch: Codable, Hashable {
    var labelEnglish: String
    var next: String

    enum CodingKeys: String, CodingKey {
        case next
        case labelEnglish = "label_english"
    }
}

struct TranscriptLine: Codable, Hashable {
    struct LineAudio: Codable, Hashable {
        var fast: String
        var slow: String
    }

    var lineId: String
    var speaker: Int               // 1 or 2 → ListenEpisode.speakerLabels
    var frenchStreet: String
    var english: String
    var audioRefs: LineAudio

    enum CodingKeys: String, CodingKey {
        case speaker, english
        case lineId = "line_id"
        case frenchStreet = "french_street"
        case audioRefs = "audio_refs"
    }
}

struct ComprehensionQuestion: Codable, Hashable {
    var question: String
    var options: [String]
    var answerIndex: Int

    enum CodingKeys: String, CodingKey {
        case question, options
        case answerIndex = "answer_index"
    }
}

// MARK: - Pack decoding

/// Decodes the static `content_pack_v2/` bundle folder produced by the
/// pipeline's `assemble_pack_v2.py` (manifest.json + learn/ + speak/ +
/// listen/ + read/ + english_prompts/).
enum ContentPackV2 {
    static let subdirectory = "content_pack_v2"

    /// Where each module's audio lives inside the pack.
    enum AudioModule: String {
        case learn, speak, listen
        case englishPrompts = "english_prompts"

        var subdirectory: String {
            switch self {
            case .englishPrompts: "\(ContentPackV2.subdirectory)/\(rawValue)"
            default: "\(ContentPackV2.subdirectory)/\(rawValue)/audio"
            }
        }
    }

    // MARK: Manifest

    struct Manifest: Decodable {
        var packVersion: Int
        var content: Content

        enum CodingKeys: String, CodingKey {
            case content
            case packVersion = "pack_version"
        }

        struct Content: Decodable {
            var learn: Learn
            var speak: Speak
            var listen: Listen
            var read: Read
        }

        struct Learn: Decodable {
            var conjugation: Counts
            var vocab: Counts
            var grammar: Counts

            struct Counts: Decodable {
                var nodes: Int
                var drills: Int
            }
        }

        struct Speak: Decodable {
            var scenarios: Int
            var variants: Int
        }

        struct Listen: Decodable {
            var episodes: Int
            var lines: Int
        }

        struct Read: Decodable {
            var passages: Int
            var questions: Int
        }
    }

    // MARK: Learn modules

    enum LearnModule: String, CaseIterable {
        case conjugation, vocab, grammar
    }

    struct LearnFile: Decodable {
        var version: Int
        var nodes: [LearnNode]
    }

    /// Superset of the three Learn node shapes; per-module fields optional.
    /// Conjugation tables and vocab word lists are NOT persisted to SwiftData —
    /// the phase-10 players read them from the pack at runtime.
    struct LearnNode: Decodable {
        var id: String
        var type: String
        var tier: Int
        var prereqIds: [String]
        var title: String
        var explanation: String?          // conjugation + grammar
        var streetNotes: String?          // conjugation
        var canonicalExamples: [CanonicalExample]?  // grammar
        var drills: [Drill]

        enum CodingKeys: String, CodingKey {
            case id, type, tier, title, explanation, drills
            case prereqIds = "prereq_ids"
            case streetNotes = "street_notes"
            case canonicalExamples = "canonical_examples"
        }
    }

    struct Drill: Decodable {
        var id: String
        var english: String
        var frenchFormal: String
        var frenchStreet: String
        var targetConceptId: String
        var conceptIds: [String]

        enum CodingKeys: String, CodingKey {
            case id, english
            case frenchFormal = "french_formal"
            case frenchStreet = "french_street"
            case targetConceptId = "target_concept_id"
            case conceptIds = "concept_ids"
        }
    }

    // MARK: Speak / Listen / Read files

    struct ScenariosFile: Decodable {
        var version: Int
        var scenarios: [PackScenario]
    }

    struct PackScenario: Decodable {
        var id: String
        var title: String
        var icon: String
        var settingBlurb: String
        var difficulty: Int
        var variants: [ScenarioVariant]

        enum CodingKeys: String, CodingKey {
            case id, title, icon, difficulty, variants
            case settingBlurb = "setting_blurb"
        }
    }

    struct EpisodesFile: Decodable {
        var version: Int
        var episodes: [PackEpisode]
    }

    struct PackEpisode: Decodable {
        struct Speaker: Decodable {
            var label: String
        }
        struct FullAudio: Decodable {
            var fullFast: String
            var fullSlow: String

            enum CodingKeys: String, CodingKey {
                case fullFast = "full_fast"
                case fullSlow = "full_slow"
            }
        }

        var id: String
        var title: String
        var level: String
        var topic: String
        var speakers: [Speaker]
        var estDurationSec: Int
        var lines: [TranscriptLine]
        var questions: [ComprehensionQuestion]
        var audioRefs: FullAudio

        enum CodingKeys: String, CodingKey {
            case id, title, level, topic, speakers, lines, questions
            case estDurationSec = "est_duration_sec"
            case audioRefs = "audio_refs"
        }
    }

    struct PassagesFile: Decodable {
        var version: Int
        var passages: [PackPassage]
    }

    struct PackPassage: Decodable {
        var id: String
        var title: String
        var style: String
        var tier: Int
        var topic: String
        var body: String
        var wordCount: Int
        var gloss: [String: String]
        var questions: [ComprehensionQuestion]

        enum CodingKeys: String, CodingKey {
            case id, title, style, tier, topic, body, gloss, questions
            case wordCount = "word_count"
        }
    }

    // MARK: Loaders

    static func loadManifest() throws -> Manifest {
        try decode(Manifest.self, resource: "manifest", subdirectory: subdirectory)
    }

    static func loadLearn(_ module: LearnModule) throws -> LearnFile {
        try decode(LearnFile.self, resource: module.rawValue,
                   subdirectory: "\(subdirectory)/learn")
    }

    static func loadScenarios() throws -> ScenariosFile {
        try decode(ScenariosFile.self, resource: "scenarios",
                   subdirectory: "\(subdirectory)/speak")
    }

    static func loadEpisodes() throws -> EpisodesFile {
        try decode(EpisodesFile.self, resource: "episodes",
                   subdirectory: "\(subdirectory)/listen")
    }

    static func loadPassages() throws -> PassagesFile {
        try decode(PassagesFile.self, resource: "passages",
                   subdirectory: "\(subdirectory)/read")
    }

    /// Resolves an audio file name like `scn_cafe_v2_n01_street_fast.mp3`
    /// to its bundle URL within the given module's audio directory.
    static func audioURL(fileName: String, module: AudioModule) -> URL? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(
            forResource: base,
            withExtension: ext.isEmpty ? "mp3" : ext,
            subdirectory: module.subdirectory
        )
    }

    private static func decode<T: Decodable>(
        _ type: T.Type, resource: String, subdirectory: String
    ) throws -> T {
        guard let url = Bundle.main.url(
            forResource: resource, withExtension: "json", subdirectory: subdirectory
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: "\(subdirectory)/\(resource).json (app bundle)"
            ])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
