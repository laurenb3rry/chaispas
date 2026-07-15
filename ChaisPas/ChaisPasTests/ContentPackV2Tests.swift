//
//  ContentPackV2Tests.swift
//  ChaisPasTests
//
//  Runs against the real app bundle (the test target hosts in ChaisPas.app),
//  so these verify content_pack_v2 is actually wired into the bundle and that
//  every decoder matches the shipped JSON. Counts assert against the
//  manifest, not hardcoded numbers, so a pipeline re-run can't silently
//  desynchronize pack and app.
//

import AVFoundation
import Foundation
import Testing
@testable import ChaisPas

struct ContentPackV2Tests {
    @Test func manifestDecodes() throws {
        let manifest = try ContentPackV2.loadManifest()
        #expect(manifest.packVersion == 2)
        #expect(manifest.content.speak.scenarios > 0)
    }

    @Test func learnModulesMatchManifest() throws {
        let learn = try ContentPackV2.loadManifest().content.learn
        for (module, counts) in [
            (ContentPackV2.LearnModule.conjugation, learn.conjugation),
            (.vocab, learn.vocab),
            (.grammar, learn.grammar),
        ] {
            let file = try ContentPackV2.loadLearn(module)
            #expect(file.nodes.count == counts.nodes)
            #expect(file.nodes.reduce(0) { $0 + $1.drills.count } == counts.drills)
            #expect(file.nodes.allSatisfy { ConceptType(rawValue: $0.type) != nil })
        }
    }

    @Test func scenariosDecodeWithBranchingIntact() throws {
        let manifest = try ContentPackV2.loadManifest().content.speak
        let scenarios = try ContentPackV2.loadScenarios().scenarios
        #expect(scenarios.count == manifest.scenarios)
        #expect(scenarios.reduce(0) { $0 + $1.variants.count } == manifest.variants)
        // every non-terminal node must carry next or branches, per schema
        for scenario in scenarios {
            for variant in scenario.variants {
                for node in variant.nodes {
                    #expect(node.speaker == "npc" || node.speaker == "user")
                    if node.branches == nil, node.next == nil {
                        #expect(node.nodeId == variant.nodes.last?.nodeId
                                || variant.nodes.contains { $0.branches?.contains {
                                    $0.next == node.nodeId } ?? false }
                                || variant.nodes.contains { $0.next == node.nodeId })
                    }
                }
            }
        }
    }

    @Test func episodesDecode() throws {
        let manifest = try ContentPackV2.loadManifest().content.listen
        let episodes = try ContentPackV2.loadEpisodes().episodes
        #expect(episodes.count == manifest.episodes)
        #expect(episodes.reduce(0) { $0 + $1.lines.count } == manifest.lines)
        #expect(episodes.allSatisfy { $0.speakers.count == 2 })
        #expect(episodes.allSatisfy { $0.questions.count == 3 })
    }

    @Test func passagesDecode() throws {
        let manifest = try ContentPackV2.loadManifest().content.read
        let passages = try ContentPackV2.loadPassages().passages
        #expect(passages.count == manifest.passages)
        #expect(passages.reduce(0) { $0 + $1.questions.count } == manifest.questions)
        #expect(passages.allSatisfy { !$0.gloss.isEmpty })
        #expect(passages.allSatisfy { (0...3).contains($0.tier) })
    }

    /// One real audio file per module: it must resolve from the bundle, be
    /// non-empty on disk, and decode in AVAudioPlayer (duration > 0) — the
    /// same player the app uses, so a passing run means any remaining
    /// playback failure is environmental (audio session / simulator output),
    /// not the pack, the paths, or the decode.
    @Test func audioResolvesNonEmptyAndDecodesForEachModule() throws {
        // learn: first conjugation drill
        let drill = try #require(
            ContentPackV2.loadLearn(.conjugation).nodes.first?.drills.first)
        // speak: first scenario node's fast street line
        let node = try #require(
            ContentPackV2.loadScenarios().scenarios.first?.variants.first?.nodes.first)
        let speakFile = try #require(node.audioRefs?["street_fast"])
        // listen: first episode's assembled (concatenated) full-fast file
        let episode = try #require(ContentPackV2.loadEpisodes().episodes.first)

        let files: [(String, ContentPackV2.AudioModule)] = [
            ("\(drill.id)_formal.mp3", .learn),
            (speakFile, .speak),
            (episode.audioRefs.fullFast, .listen),
            ("\(drill.id)_english.mp3", .englishPrompts),
        ]
        for (file, module) in files {
            let url = try #require(ContentPackV2.audioURL(fileName: file, module: module),
                                   "unresolved: \(module)/\(file)")
            let size = try #require(
                try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
                "unreadable: \(module)/\(file)")
            #expect(size > 0, "empty file: \(module)/\(file)")

            let player = try AVAudioPlayer(contentsOf: url)
            #expect(player.duration > 0, "undecodable audio: \(module)/\(file)")
        }
    }

    @Test func payloadsRoundTrip() throws {
        let scenario = try #require(ContentPackV2.loadScenarios().scenarios.first)
        let encoded = try JSONEncoder().encode(scenario.variants)
        let decoded = try JSONDecoder().decode([ScenarioVariant].self, from: encoded)
        #expect(decoded == scenario.variants)

        let episode = try #require(ContentPackV2.loadEpisodes().episodes.first)
        let lines = try JSONDecoder().decode(
            [TranscriptLine].self, from: JSONEncoder().encode(episode.lines))
        #expect(lines == episode.lines)
    }
}
