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

    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { viewModel.appMode },
            set: { newValue in
                DispatchQueue.main.async {
                    viewModel.appMode = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Mode Switcher
            HStack {
                Spacer()
                Picker("Mode".localized, selection: modeBinding) {
                    ForEach(AppMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
                .padding(.vertical, 4)
                Spacer()
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                LeftSidebarView(viewModel: viewModel, showInfoEditor: $showInfoEditor, showAIConfig: $showAIConfig)
                    .frame(minWidth: 250, maxWidth: 350)

                CenterView(viewModel: viewModel, isBoardFocused: $isBoardFocused)
                    .frame(minWidth: 500)

                RightSidebarView(viewModel: viewModel)
                    .frame(minWidth: 250, maxWidth: 350)
            }
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
