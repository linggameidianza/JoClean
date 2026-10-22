//
//  ContentView.swift
//  JoClean
//
//  Created by ichio on 22/10/26.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case smartScan, systemJunk, trash, largeFiles, uninstaller, optimization, malware

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .systemJunk: "System Junk"
        case .trash: "Trash"
        case .largeFiles: "Large & Old Files"
        case .uninstaller: "Uninstaller"
        case .optimization: "Optimization"
        case .malware: "Malware Check"
        }
    }

    var theme: ModuleTheme {
        switch self {
        case .smartScan: .smartScan
        case .systemJunk: .systemJunk
        case .trash: .trash
        case .largeFiles: .largeFiles
        case .uninstaller: .uninstaller
        case .optimization: .optimization
        case .malware: .malware
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .smartScan
    /// Keep the sidebar (the module menu) visible; it used to auto-collapse at launch.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var current: SidebarItem { selection ?? .smartScan }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                sidebarRow(.smartScan)
                Section("Cleanup") {
                    sidebarRow(.systemJunk)
                    sidebarRow(.trash)
                }
                Section("Disk Space") {
                    sidebarRow(.largeFiles)
                }
                Section("Applications") {
                    sidebarRow(.uninstaller)
                }
                Section("Speed") {
                    sidebarRow(.optimization)
                }
                Section("Security") {
                    sidebarRow(.malware)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ZStack {
                // Each module has its own bright animated background; cross-fade when switching.
                AnimatedMeshBackground(theme: current.theme)
                    .id(current)
                    .transition(.opacity)

                // Lay the module out in exactly the space available and clip any overflow, so no module
                // can push the whole split view (including the sidebar) off-screen.
                GeometryReader { proxy in
                    detail(for: current)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
                    .id(current)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity
                    ))
            }
            .animation(.smooth(duration: 0.5), value: current)
            .environment(\.moduleTheme, current.theme)
            // White text and light-on-dark controls read best on the saturated gradients.
            .environment(\.colorScheme, .dark)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .toolbar(removing: .title)
        .frame(minWidth: 980, minHeight: 640)
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.theme.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(item.theme.gradient, in: .rect(cornerRadius: 6))
        }
        .tag(item)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan: SmartScanView()
        case .systemJunk: SystemJunkView()
        case .trash: TrashView()
        case .largeFiles: LargeFilesView()
        case .uninstaller: UninstallerView()
        case .optimization: OptimizationView()
        case .malware: MalwareCheckView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
