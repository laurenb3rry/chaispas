import Foundation

/// Decodes the static `content_pack_v1/` bundle folder (graph.json,
/// sentences.json, audio/) produced by the local content pipeline.
enum ContentPack {
    static let subdirectory = "content_pack_v1"

    struct Graph: Decodable {
        var version: Int
        var nodes: [Node]
    }

    struct Node: Decodable {
        var id: String
        var type: String
        var tier: Int
        var prereqIds: [String]
        var title: String
        var explanation: String
        var canonicalExamples: [CanonicalExample]
        var streetMapping: String

        enum CodingKeys: String, CodingKey {
            case id, type, tier, title, explanation
            case prereqIds = "prereq_ids"
            case canonicalExamples = "canonical_examples"
            case streetMapping = "street_mapping"
        }
    }

    struct Sentences: Decodable {
        var version: Int
        var sentences: [PackSentence]
    }

    struct PackSentence: Decodable {
        var id: String
        var conceptIds: [String]
        var english: String
        var frenchFormal: String
        var frenchStreet: String

        enum CodingKeys: String, CodingKey {
            case id, english
            case conceptIds = "concept_ids"
            case frenchFormal = "french_formal"
            case frenchStreet = "french_street"
        }
    }

    static func loadGraph() throws -> Graph {
        try decode(Graph.self, resource: "graph")
    }

    static func loadSentences() throws -> Sentences {
        try decode(Sentences.self, resource: "sentences")
    }

    /// Resolves an audio file name like `cest_001_formal.mp3` to its bundle URL.
    static func audioURL(fileName: String) -> URL? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(
            forResource: base,
            withExtension: ext.isEmpty ? "mp3" : ext,
            subdirectory: "\(subdirectory)/audio"
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
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
