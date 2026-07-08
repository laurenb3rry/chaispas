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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConceptNode.self,
            Sentence.self,
            DrillEvent.self,
            MasteryScore.self,
            SessionLog.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // Synchronous on purpose: ~1k rows imports in well under a second,
            // and every view can then assume the pack is present
            ContentPackImporter.importIfNeeded(context: ModelContext(container))
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
