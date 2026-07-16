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

    // MARK: Phase 10 — Learn player payloads (tables, words, examples)

    /// Phase 10b: every verb and grammar explanation is a structured section
    /// array (header + body, optional bullets/examples), in the plain expert
    /// voice — never the legacy single paragraph.
    @Test func explanationsAreStructuredSections() throws {
        for module in [ContentPackV2.LearnModule.conjugation, .grammar] {
            for node in try ContentPackV2.loadLearn(module).nodes {
                let sections = try #require(node.explanation,
                                            "\(node.id) missing structured explanation")
                #expect(!sections.isEmpty, "\(node.id): empty explanation")
                #expect(sections.allSatisfy {
                    !$0.header.isEmpty && !$0.body.isEmpty
                }, "\(node.id): section missing header/body")
                #expect(!node.explanationPlainText.isEmpty)
            }
        }
    }

    /// Phase 10b: the conjugation file carries shared tense-usage guidance
    /// for every tense tab the player shows.
    @Test func tenseUsageCoversAllFourTenses() throws {
        let usage = try #require(ContentPackV2.loadLearn(.conjugation).tenseUsage)
        for (tense, _) in ConjugationPlayerView.tenses {
            let entry = try #require(usage[tense], "missing tense_usage for \(tense)")
            #expect(!entry.label.isEmpty && !entry.note.isEmpty)
            #expect((2...3).contains(entry.contrasts.count))
            #expect(entry.contrasts.allSatisfy {
                !$0.aFrench.isEmpty && !$0.bFrench.isEmpty && !$0.point.isEmpty
            })
        }
    }

    /// Every verb node carries a full table (all four tenses × six persons)
    /// whose per-form audio — formal always, street where the form differs —
    /// resolves from the bundle under the derived naming.
    @Test func conjugationTablesCompleteWithResolvableAudio() throws {
        let nodes = try ContentPackV2.loadLearn(.conjugation).nodes
        let verbs = nodes.filter { $0.table != nil }
        // every node except the politesse mini-module is a verb with a table
        #expect(verbs.count == nodes.count - 1)

        for node in verbs {
            let table = try #require(node.table)
            for (tense, _) in ConjugationPlayerView.tenses {
                let forms = try #require(table[tense], "\(node.id) missing \(tense)")
                for person in ConjugationPlayerView.persons {
                    let form = try #require(forms[person],
                                            "\(node.id) \(tense) missing \(person)")
                    #expect(ContentPackV2.audioURL(
                        fileName: ContentPackV2.tableAudio(
                            nodeId: node.id, tense: tense, person: person),
                        module: .learn) != nil,
                        "unresolved formal audio: \(node.id) \(tense) \(person)")
                    if let street = form.street, street != form.formal {
                        #expect(ContentPackV2.audioURL(
                            fileName: ContentPackV2.tableAudio(
                                nodeId: node.id, tense: tense, person: person, street: true),
                            module: .learn) != nil,
                            "unresolved street audio: \(node.id) \(tense) \(person)")
                    }
                }
            }
        }
    }

    /// The politesse mini-module ships fixed forms instead of a table.
    @Test func politesseFormsDecodeWithResolvableAudio() throws {
        let node = try #require(ContentPackV2.learnNode(
            id: "conj_politesse_conditionnel", module: .conjugation))
        #expect(node.table == nil)
        let forms = try #require(node.forms)
        #expect(!forms.isEmpty)
        for form in forms {
            #expect(ContentPackV2.audioURL(
                fileName: ContentPackV2.namedFormAudio(nodeId: node.id, formId: form.id),
                module: .learn) != nil,
                "unresolved form audio: \(form.id)")
            if let street = form.street, street != form.formal {
                #expect(ContentPackV2.audioURL(
                    fileName: ContentPackV2.namedFormAudio(
                        nodeId: node.id, formId: form.id, street: true),
                    module: .learn) != nil,
                    "unresolved street form audio: \(form.id)")
            }
        }
    }

    /// Every vocab pack carries its 25 words, each with resolvable audio.
    @Test func vocabWordsDecodeWithResolvableAudio() throws {
        let nodes = try ContentPackV2.loadLearn(.vocab).nodes
        for node in nodes {
            let words = try #require(node.words, "\(node.id) has no words")
            #expect(words.count == 25)
        }
        // spot-check audio on the first pack (1,000 lookups would be slow)
        let first = try #require(nodes.first?.words)
        for word in first {
            #expect(ContentPackV2.audioURL(
                fileName: ContentPackV2.wordAudio(wordId: word.id),
                module: .learn) != nil,
                "unresolved word audio: \(word.id)")
        }
    }

    /// Grammar canonical examples: audio derives from the example's position
    /// (1-based `exNN`), formal + both street speeds. Full variant sweep on
    /// the first lesson; first-example resolution on every lesson (catches a
    /// new lesson whose audio never got synthesized).
    @Test func grammarExampleAudioResolves() throws {
        let nodes = try ContentPackV2.loadLearn(.grammar).nodes
        let node = try #require(nodes.first)
        let examples = try #require(node.canonicalExamples)
        #expect(!examples.isEmpty)
        for (index, _) in examples.enumerated() {
            for variant in ["formal", "street_fast", "street_slow"] {
                #expect(ContentPackV2.audioURL(
                    fileName: ContentPackV2.exampleAudio(
                        nodeId: node.id, index: index, variant: variant),
                    module: .learn) != nil,
                    "unresolved example audio: \(node.id) ex\(index + 1) \(variant)")
            }
        }
        for other in nodes {
            #expect(ContentPackV2.audioURL(
                fileName: ContentPackV2.exampleAudio(nodeId: other.id, index: 0),
                module: .learn) != nil,
                "unresolved first example audio for \(other.id)")
        }
    }

    /// The pack-aware resolver behind drill playback: v2 drills resolve in
    /// the learn module, v1 sentences in the v1 pack, prompts in
    /// english_prompts — through the one AudioPlayer entry point.
    @Test func audioPlayerLocationsResolve() throws {
        let drill = try #require(
            ContentPackV2.loadLearn(.grammar).nodes.first?.drills.first)
        #expect(AudioPlayer.url(fileName: "\(drill.id)_formal.mp3", in: .v2Learn) != nil)
        #expect(AudioPlayer.url(fileName: "\(drill.id)_english.mp3", in: .englishPrompts) != nil)
        let v1 = try #require(ContentPack.loadSentences().sentences.first)
        #expect(AudioPlayer.url(fileName: "\(v1.id)_formal.mp3", in: .v1) != nil)
        // wrong location must not resolve — the directories really are distinct
        #expect(AudioPlayer.url(fileName: "\(drill.id)_formal.mp3", in: .v1) == nil)
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
