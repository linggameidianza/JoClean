//
//  TrashView.swift
//  JoClean
//

import SwiftUI
import AppKit

struct TrashView: View {
    @Environment(AppState.self) private var appState
    @State private var isConfirmingEmpty = false

    private var model: TrashModel { appState.trash }

    private enum Phase: Hashable { case welcome, scanning, needsPermission, empty, results }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        if !model.hasScanned { return .welcome }
        if model.needsPermission { return .needsPermission }
        return model.itemCount == 0 ? .empty : .results
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(cornerRadius: 14)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            ZStack {
                switch phase {
                case .welcome:
                    ScanPromptView(
                        title: "Trash",
                        message: "See how much space the Trash is using, then empty it in one click."
                    ) {
                        Task { await model.scan() }
                    }
                    .transition(.blurReplace)
                case .scanning:
                    ScanningView(message: "Measuring the Trash…")
                        .transition(.blurReplace)
                case .needsPermission:
                    TrashPermissionView {
                        Task { await model.scan() }
                    }
                    .transition(.blurReplace)
                case .empty:
                    CompletionView(
                        title: "Trash Is Empty",
                        message: model.lastResult.map { "\($0.removedBytes.formattedBytes) permanently deleted." }
                            ?? "There’s nothing to clean.",
                        buttonTitle: "Check Again"
                    ) {
                        Task { await model.scan() }
                    }
                    .transition(.blurReplace)
                case .results:
                    results
                        .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.5), value: phase)
        }
        .toolbar {
            ToolbarItem {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    Task { await model.scan() }
                }
                .disabled(model.isScanning || model.isEmptying)
            }
        }
        .confirmationDialog("Empty the Trash?", isPresented: $isConfirmingEmpty) {
            Button("Delete Permanently", role: .destructive) {
                Task { await model.empty() }
            }
        } message: {
            Text("\(sizeText) in \(model.itemCount) items will be permanently deleted. This can’t be undone.")
        }
    }

    /// "1,2 GB", or "at least 1,2 GB" when Finder didn't report every size.
    private var sizeText: String {
        model.sizeIsIncomplete ? "At least \(model.totalSize.formattedBytes)" : model.totalSize.formattedBytes
    }

    private var results: some View {
        VStack(spacing: 12) {
            FeatureHeader(
                title: "Trash",
                subtitle: model.accessMode == .finder
                    ? "\(model.itemCount) items • read through Finder (grant Full Disk Access for exact sizes)."
                    : "\(model.itemCount) items using \(model.totalSize.formattedBytes)."
            )

            List(model.items) { item in
                HStack(spacing: 12) {
                    FileIcon(url: item.url, size: 24)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.size > 0 ? item.size.formattedBytes : "—")
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
                .padding(.vertical, 3)
                .listRowBackground(Color.clear)
                .contextMenu { FileContextMenu(url: item.url) }
            }
            .transparentScrollBackground()
            .glassPanel()
            .padding(.horizontal, 24)

            ActionBar(
                summary: sizeText,
                detail: "\(model.itemCount) items in the Trash",
                buttonTitle: "Empty",
                isWorking: model.isEmptying,
                isDisabled: model.itemCount == 0
            ) {
                isConfirmingEmpty = true
            }
        }
    }
}

/// Explains why the Trash can't be read and how to fix it.
private struct TrashPermissionView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            HeroIcon(systemImage: "lock.shield.fill", size: 120)

            VStack(spacing: 8) {
                Text("JoClean Can’t See Your Trash")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("macOS protects the Trash. Choose one of these, then click Try Again:")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                option(
                    systemImage: "hand.tap.fill",
                    title: "Allow JoClean to control Finder",
                    message: "Finder reads and empties the Trash for JoClean. Turn on Finder under JoClean in Automation settings.",
                    buttonTitle: "Open Automation",
                    settingsAnchor: "Privacy_Automation"
                )
                option(
                    systemImage: "externaldrive.fill.badge.checkmark",
                    title: "Grant Full Disk Access",
                    message: "Lets JoClean read the Trash directly and show exact sizes.",
                    buttonTitle: "Open Full Disk Access",
                    settingsAnchor: "Privacy_AllFiles"
                )
            }
            .padding(16)
            .frame(maxWidth: 620)
            .glassPanel()

            Spacer(minLength: 8)
            RoundActionButton(title: "Try Again", diameter: 92, action: retry)
                .padding(.bottom, 24)
        }
        .padding(.horizontal)
    }

    private func option(systemImage: String, title: String, message: String, buttonTitle: String, settingsAnchor: String) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
            }
            Spacer()
            Button(buttonTitle) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glass)
        }
    }
}
