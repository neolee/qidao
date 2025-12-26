//
//  ContentView.swift
//  QiDao
//
//  Created by Neo on 2025/12/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel()
    @State private var showInfoEditor = false
    @State private var showEngineConfig = false
    @FocusState private var isBoardFocused: Bool

    var body: some View {
        HSplitView {
            LeftSidebarView(viewModel: viewModel, showInfoEditor: $showInfoEditor, showEngineConfig: $showEngineConfig)
            
            CenterView(viewModel: viewModel, isBoardFocused: $isBoardFocused)
                .frame(minWidth: 400)
            
            RightSidebarView(viewModel: viewModel)
        }
        .sheet(isPresented: $showInfoEditor) {
            GameInfoEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showEngineConfig) {
            // Placeholder for Engine Config View
            VStack(spacing: 20) {
                Text("AI Engine Configuration").font(.headline)
                Text("Settings will be implemented in Phase 2").foregroundColor(.secondary)
                Button("Close") { showEngineConfig = false }
            }
            .padding()
            .frame(width: 400, height: 300)
        }
        .onAppear {
            isBoardFocused = true
        }
    }
}

#Preview {
    ContentView()
}
