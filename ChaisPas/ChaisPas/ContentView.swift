//
//  ContentView.swift
//  ChaisPas
//
//  Created by Lauren Berry on 7/7/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            DSColor.background.ignoresSafeArea()
            VStack(spacing: DSSpacing.lg) {
                Text("Chais Pas")
                    .font(DSType.largeTitle)
                    .tracking(DSType.largeTitleTracking)
                    .foregroundStyle(DSColor.textPrimary)
                Text("C'est pas grave.")
                    .font(DSType.french)
                    .foregroundStyle(DSColor.accent)
                Text("Phase 1 scaffold — models + design system")
                    .font(DSType.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.horizontal, DSSpacing.margin)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
