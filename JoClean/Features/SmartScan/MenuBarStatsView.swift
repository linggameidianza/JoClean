//
//  MenuBarStatsView.swift
//  JoClean
//

import SwiftUI
import AppKit

/// Compact system status shown from the menu bar icon.
struct MenuBarStatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let monitor = appState.monitor
        VStack(alignment: .leading, spacing: 14) {
            Text("JoClean")
                .font(.headline)

            statRow(
                title: "Disk",
                systemImage: "internaldrive",
                fraction: monitor.diskFraction,
                detail: "\(monitor.diskAvailable.formattedBytes) available",
                tint: .blue
            )
            statRow(
                title: "Memory",
                systemImage: "memorychip",
                fraction: monitor.memoryFraction,
                detail: "\(monitor.memoryUsed.formattedBytes) of \(monitor.memoryTotal.formattedBytes)",
                tint: .purple
            )
            statRow(
                title: "CPU",
                systemImage: "cpu",
                fraction: monitor.cpuUsage,
                detail: monitor.cpuUsage.formatted(.percent.precision(.fractionLength(0))),
                tint: .orange
            )

            Divider()

            HStack {
                Button("Open JoClean") {
                    openWindow(id: JoCleanApp.mainWindowID)
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func statRow(title: String, systemImage: String, fraction: Double, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(tint)
        }
    }
}
