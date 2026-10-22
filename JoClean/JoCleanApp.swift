//
//  JoCleanApp.swift
//  JoClean
//
//  Created by ichio on 22/10/26.
//

import SwiftUI

@main
struct JoCleanApp: App {
    static let mainWindowID = "main"

    @State private var appState = AppState()

    init() {
        // AppKit restored a saved session in which the main window had been closed, so SwiftUI
        // treated launch as "already restored" and never opened a window (only the menu bar icon
        // appeared). Ignoring persisted window state guarantees a fresh main window on every launch.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        // WindowGroup is the primary scene and is reliably presented at launch.
        // (A single `Window` scene was sometimes never opened, leaving only the menu bar item.)
        WindowGroup("JoClean", id: Self.mainWindowID) {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1100, height: 760)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarStatsView()
                .environment(appState)
        } label: {
            Label("JoClean", systemImage: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}
