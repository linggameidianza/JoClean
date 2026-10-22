//
//  OptimizationView.swift
//  JoClean
//

import SwiftUI

struct OptimizationView: View {
    @Environment(AppState.self) private var appState
    @State private var agentToRemove: LaunchAgent?

    private var model: OptimizationModel { appState.optimization }

    var body: some View {
        ZStack {
            if model.isScanning {
                ScanningView(message: "Checking running apps and launch agents…")
                    .transition(.blurReplace)
            } else if !model.hasScanned {
                // Nothing runs until the user explicitly starts the scan.
                ScanPromptView(
                    title: "Optimization",
                    message: "Find memory-hungry apps and programs that start automatically at login."
                ) {
                    Task { await model.refresh() }
                }
                .transition(.blurReplace)
            } else {
                results
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.5), value: model.isScanning)
        .animation(.smooth(duration: 0.5), value: model.hasScanned)
        .toolbar {
            ToolbarItem {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(model.isScanning)
            }
        }
        .confirmationDialog(
            "Remove launch agent \"\(agentToRemove?.label ?? "")\"?",
            isPresented: Binding(
                get: { agentToRemove != nil },
                set: { if !$0 { agentToRemove = nil } }
            ),
            presenting: agentToRemove
        ) { agent in
            Button("Move to Trash", role: .destructive) {
                Task { await model.remove(agent) }
            }
        } message: { _ in
            Text("This program won’t start automatically at your next login.")
        }
    }

    private var results: some View {
        VStack(spacing: 12) {
            FeatureHeader(
                title: "Optimization",
                subtitle: "Quit memory-hungry apps and manage programs that run at login."
            )

            if let result = model.lastResult {
                RemovalResultBanner(result: result)
            }

            ScrollView {
                VStack(spacing: 16) {
                    section(
                        title: "Running Apps",
                        subtitle: "Sorted by memory usage",
                        systemImage: "memorychip.fill"
                    ) {
                        ForEach(model.runningApps) { info in
                            runningAppRow(info)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }

                    section(
                        title: "Launch Agents",
                        subtitle: "Background programs that run at login. Changes take effect after you log out.",
                        systemImage: "gearshape.2.fill"
                    ) {
                        if model.launchAgents.isEmpty {
                            Text("No user launch agents.")
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.vertical, 8)
                        }
                        ForEach(model.launchAgents) { agent in
                            launchAgentRow(agent)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .animation(.smooth, value: model.runningApps.map(\.id))
                .animation(.smooth, value: model.launchAgents)
            }
            .scrollIndicators(.never)
        }
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconTile(systemImage: systemImage, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.bottom, 4)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private func runningAppRow(_ info: RunningAppInfo) -> some View {
        HStack(spacing: 12) {
            if let icon = info.app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            Text(info.name)
            Spacer()
            MemoryBar(bytes: info.memory)
            Button("Quit") {
                model.quit(info)
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Force Quit") { model.quit(info, force: true) }
        }
    }

    private func launchAgentRow(_ agent: LaunchAgent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(agent.label)
                if let program = agent.program {
                    Text(program)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button("Remove") {
                agentToRemove = agent
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 2)
        .contextMenu { FileContextMenu(url: agent.url) }
    }
}

/// Memory amount with a small bar scaled against 4 GB.
private struct MemoryBar: View {
    let bytes: UInt64

    private var fraction: Double { min(Double(bytes) / 4_000_000_000, 1) }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 80, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: max(80 * fraction, 4), height: 6)
                }
            Text(bytes.formattedBytes)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
                .fontWeight(bytes > 1_000_000_000 ? .bold : .regular)
        }
    }
}
