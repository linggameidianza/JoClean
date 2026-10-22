//
//  TrashView.swift
//  JoClean
//

import SwiftUI

struct TrashView: View {
    @Environment(AppState.self) private var appState
    @State private var isConfirmingEmpty = false

    private var model: TrashModel { appState.trash }

    private enum Phase: Hashable { case welcome, scanning, empty, results }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        if !model.hasScanned { return .welcome }
        return model.items.isEmpty ? .empty : .results
    }

    var body: some View {
        VStack(spacing: 8) {
            if model.needsFullDiskAccess {
                FullDiskAccessHint()
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
                case .empty:
                    CompletionView(
                        title: "Trash Is Empty",
                        message: model.lastResult.map { "\($0.removedBytes.formattedBytes) telah dihapus permanen." }
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
            Text("\(model.totalSize.formattedBytes) will be permanently deleted. This can’t be undone.")
        }
    }

    private var results: some View {
        VStack(spacing: 12) {
            FeatureHeader(
                title: "Trash",
                subtitle: "\(model.items.count) items using \(model.totalSize.formattedBytes)."
            )

            List(model.items) { item in
                HStack(spacing: 12) {
                    FileIcon(url: item.url, size: 24)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.size.formattedBytes)
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
                summary: model.totalSize.formattedBytes,
                detail: "\(model.items.count) items in the Trash",
                buttonTitle: "Empty",
                isWorking: model.isEmptying,
                isDisabled: model.items.isEmpty
            ) {
                isConfirmingEmpty = true
            }
        }
    }
}
