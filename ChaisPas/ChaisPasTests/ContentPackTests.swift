//
//  ContentPackTests.swift
//  ChaisPasTests
//
//  Runs against the real app bundle (the test target hosts in ChaisPas.app),
//  so these verify the content pack is actually wired into the bundle.
//

import Foundation
import Testing
@testable import ChaisPas

struct ContentPackTests {
    @Test func graphDecodesWithAllNodes() throws {
        let graph = try ContentPack.loadGraph()
        #expect(graph.nodes.count == 25)
        #expect(graph.nodes.allSatisfy { ConceptType(rawValue: $0.type) != nil })
    }

    @Test func sentencesDecode() throws {
        let sentences = try ContentPack.loadSentences().sentences
        #expect(sentences.count == 959)
        #expect(sentences.allSatisfy { !$0.conceptIds.isEmpty })
    }

    @Test func audioResolvesFromBundle() throws {
        let first = try #require(ContentPack.loadSentences().sentences.first)
        for file in [
            "\(first.id)_formal.mp3",
            "\(first.id)_street_slow.mp3",
            "\(first.id)_street_fast.mp3",
        ] {
            let url = try #require(ContentPack.audioURL(fileName: file))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
