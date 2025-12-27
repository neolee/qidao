//
//  QiDaoApp.swift
//  QiDao
//
//  Created by Neo on 2025/12/24.
//

import SwiftUI
import Sparkle

@main
struct QiDaoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var langManager = LanguageManager.shared
    private let updaterController: SPUStandardUpdaterController

    init() {
        // If you want to customize the updater, you can do it here
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .printItem) { }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...".localized) {
                    updaterController.checkForUpdates(nil)
                }
                .keyboardShortcut("U", modifiers: [.command, .shift])
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
