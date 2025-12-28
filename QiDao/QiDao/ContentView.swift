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
    @State private var showAIConfig = false
    @FocusState private var isBoardFocused: Bool

    var body: some View {
        HSplitView {
            LeftSidebarView(viewModel: viewModel, showInfoEditor: $showInfoEditor, showAIConfig: $showAIConfig)
                .frame(minWidth: 250, maxWidth: 350)

            CenterView(viewModel: viewModel, isBoardFocused: $isBoardFocused)
                .frame(minWidth: 500)

            RightSidebarView(viewModel: viewModel)
                .frame(minWidth: 250, maxWidth: 350)
        }
        .sheet(isPresented: $showInfoEditor) {
            GameInfoEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAIConfig) {
            AIConfigView(viewModel: viewModel)
        }
        .onAppear {
            isBoardFocused = true
        }
    }
}

#Preview {
    ContentView()
}
