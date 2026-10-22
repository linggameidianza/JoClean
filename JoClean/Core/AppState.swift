//
//  AppState.swift
//  JoClean
//

import Foundation

/// Owns every feature model so state survives switching between sidebar sections.
@Observable
final class AppState {
    let monitor = SystemMonitor()
    let junk = JunkCleanerModel()
    let trash = TrashModel()
    let largeFiles = LargeFilesModel()
    let uninstaller = UninstallerModel()
    let optimization = OptimizationModel()
    let malware = MalwareCheckModel()

    init() {
        monitor.start()
    }
}
