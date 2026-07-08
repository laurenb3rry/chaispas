import Foundation

enum ConceptType: String, Codable {
    case construction
    case chunk
    case vocabCluster = "vocab_cluster"
    case register
    case constructionRegister = "construction+register"
}

enum DrillAxis: String, Codable {
    case production
    case comprehension
    case shadow
}

struct CanonicalExample: Codable, Hashable {
    var english: String
    var formal: String
    var street: String
}

struct AudioRefs: Codable, Hashable {
    var formal: String
    var streetSlow: String
    var streetFast: String
}
