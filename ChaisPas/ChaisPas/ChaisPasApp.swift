//
//  ChaisPasApp.swift
//  ChaisPas
//
//  Created by Lauren Berry on 7/7/26.
//

import SwiftUI
import SwiftData

@main
struct ChaisPasApp: App {
    let sharedModelContainer: ModelContainer
    // Decided once at launch with cheap fetchCounts: populated stores render
    // ContentView immediately; the pack import itself runs async in RootView
    let needsImport: Bool

    init() {
        let schema = Schema([
            ConceptNode.self,
            Sentence.self,
            DrillEvent.self,
            MasteryScore.self,
            SessionLog.self,
            Scenario.self,
            ListenEpisode.self,
            Passage.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            sharedModelContainer = container
            needsImport = ContentPackImporter.needsWork(context: ModelContext(container))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(needsImport: needsImport)
        }
        .modelContainer(sharedModelContainer)
    }
}
