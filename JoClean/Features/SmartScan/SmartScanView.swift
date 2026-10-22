//
//  SmartScanView.swift
//  JoClean
//

import SwiftUI

/// Dashboard with live system stats and a one-click scan of junk + Trash.
struct SmartScanView: View {
    @Environment(AppState.self) private var appState
    @State private var includeTrash = true
    @State private var isConfirmingClean = false
    @State private var isCleaning = false
    @State private var cleanedBytes: Int64?

    private enum Phase: Hashable { case welcome, scanning, results, cleaning, done }

    private var phase: Phase {
        if isCleaning { return .cleaning }
        if cleanedBytes != nil { return .done }
        if appState.junk.isScanning || appState.trash.isScanning { return .scanning }
        if appState.junk.hasScanned && appState.trash.hasScanned { return .results }
        return .welcome
    }

    private var reclaimable: Int64 {
        appState.junk.selectedSize + (includeTrash ? appState.trash.totalSize : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            statsRow
                .padding(.horizontal, 24)
                .padding(.top, 12)

            ZStack {
                switch phase {
                case .welcome:
                    ScanPromptView(
                        title: "Welcome to JoClean",
                        message: "Start with a quick scan to find system junk and space you can free up.",
                        systemImage: "desktopcomputer"
                    ) {
                        Task { await scan() }
                    }
                    .transition(.blurReplace)
                case .scanning:
                    ScanningView(message: "Scanning caches, logs, and the Trash…", systemImage: "desktopcomputer")
                        .transition(.blurReplace)
                case .results, .cleaning:
                    results
                        .transition(.blurReplace)
                case .done:
                    CompletionView(
                        title: "\((cleanedBytes ?? 0).formattedBytes) cleaned",
                        message: "Your Mac has more room now. Run Smart Scan again anytime.",
                        buttonTitle: "Done"
                    ) {
                        cleanedBytes = nil
                    }
                    .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.5), value: phase)
        }
        .confirmationDialog("Clean \(reclaimable.formattedBytes)?", isPresented: $isConfirmingClean) {
            Button("Clean", role: .destructive) {
                Task { await clean() }
            }
        } message: {
            Text(includeTrash
                 ? "System junk will be removed and the Trash will be emptied permanently."
                 : "System junk will be moved to the Trash.")
        }
    }

    // MARK: Sections

    /// Separate view so live stat updates only re-render the cards, not the whole screen.
    private var statsRow: some View {
        StatsRow(monitor: appState.monitor)
    }

    private var results: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text("Ready to clean")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(reclaimable.formattedBytes)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(value: Double(reclaimable)))
                    .animation(.smooth, value: reclaimable)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            }

            HStack(spacing: 16) {
                SummaryTile(
                    title: "System Junk",
                    systemImage: "trash.circle.fill",
                    size: appState.junk.selectedSize,
                    isIncluded: nil
                )
                SummaryTile(
                    title: "Trash",
                    systemImage: "trash.fill",
                    size: appState.trash.totalSize,
                    isIncluded: $includeTrash
                )
            }
            .frame(maxWidth: 560)

            if appState.trash.needsFullDiskAccess {
                FullDiskAccessHint()
                    .frame(maxWidth: 620)
            }

            Spacer(minLength: 0)

            HStack(spacing: 28) {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    Task { await scan() }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(isCleaning)

                RoundActionButton(
                    title: "Clean",
                    isWorking: isCleaning,
                    isDisabled: reclaimable == 0
                ) {
                    isConfirmingClean = true
                }

                // Balances the button on the left so the round button stays centered.
                Color.clear.frame(width: 120, height: 1)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    // MARK: Actions

    private func scan() async {
        async let junk: Void = appState.junk.scan()
        async let trash: Void = appState.trash.scan()
        _ = await (junk, trash)
    }

    private func clean() async {
        let expected = reclaimable
        isCleaning = true
        await appState.junk.cleanSelected()
        if includeTrash {
            // Rescan so the junk that was just moved to the Trash is deleted as well.
            await appState.trash.scan()
            await appState.trash.empty()
        }
        isCleaning = false
        cleanedBytes = expected
    }
}

/// Live Disk / Memory / CPU cards. Reading the monitor here (rather than in SmartScanView)
/// keeps the 2-second updates from invalidating the rest of the screen.
private struct StatsRow: View {
    let monitor: SystemMonitor

    var body: some View {
        HStack(spacing: 14) {
            StatCard(
                title: "Disk",
                systemImage: "internaldrive.fill",
                fraction: monitor.diskFraction,
                detail: "\(monitor.diskAvailable.formattedBytes) available"
            )
            StatCard(
                title: "Memory",
                systemImage: "memorychip.fill",
                fraction: monitor.memoryFraction,
                detail: "\(monitor.memoryUsed.formattedBytes) / \(monitor.memoryTotal.formattedBytes)"
            )
            StatCard(
                title: "CPU",
                systemImage: "cpu.fill",
                fraction: monitor.cpuUsage,
                detail: "Processor load"
            )
        }
    }
}

/// Glass card with a circular usage ring.
private struct StatCard: View {
    let title: String
    let systemImage: String
    let fraction: Double
    let detail: String
    @Environment(\.appearsActive) private var appearsActive

    /// Animate value changes only while the window is active, so background updates are nearly free.
    private var valueAnimation: Animation? { appearsActive ? .smooth(duration: 0.5) : nil }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(valueAnimation, value: fraction)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText(value: fraction))
                        .animation(valueAnimation, value: fraction)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 18)
    }
}

/// One category in the Smart Scan summary.
private struct SummaryTile: View {
    let title: String
    let systemImage: String
    let size: Int64
    let isIncluded: Binding<Bool>?

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(size.formattedBytes)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(size)))
            }
            Spacer()
            if let isIncluded {
                Toggle("", isOn: isIncluded)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 18)
    }
}

#Preview {
    ZStack {
        AnimatedMeshBackground(theme: .smartScan)
        SmartScanView()
    }
    .environment(AppState())
    .environment(\.colorScheme, .dark)
    .frame(width: 720, height: 640)
}
