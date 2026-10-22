//
//  SystemJunkView.swift
//  JoClean
//

import SwiftUI

struct SystemJunkView: View {
    @Environment(AppState.self) private var appState
    @State private var isConfirmingClean = false

    private var model: JunkCleanerModel { appState.junk }

    private enum Phase: Hashable { case welcome, scanning, results }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        return model.hasScanned ? .results : .welcome
    }

    var body: some View {
        ZStack {
            switch phase {
            case .welcome:
                ScanPromptView(
                    title: "System Junk",
                    message: "Find caches, logs, and leftover build files that are safe to remove."
                ) {
                    Task { await model.scan() }
                }
                .transition(.blurReplace)
            case .scanning:
                ScanningView(message: "Scanning caches, logs, and temporary files…")
                    .transition(.blurReplace)
            case .results:
                results
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.5), value: phase)
        .toolbar {
            ToolbarItem {
                Button("Scan Again", systemImage: "arrow.clockwise") {
                    Task { await model.scan() }
                }
                .disabled(model.isScanning || model.isCleaning)
            }
        }
        .confirmationDialog(
            "Move \(model.selectedItems.count) items (\(model.selectedSize.formattedBytes)) to the Trash?",
            isPresented: $isConfirmingClean
        ) {
            Button("Clean", role: .destructive) {
                Task { await model.cleanSelected() }
            }
        } message: {
            Text("Apps that are running may recreate their caches.")
        }
    }

    private var results: some View {
        VStack(spacing: 12) {
            FeatureHeader(
                title: "System Junk",
                subtitle: "Found \(model.totalSize.formattedBytes) of files you can clean."
            )

            if let result = model.lastResult {
                RemovalResultBanner(result: result)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(JunkCategory.allCases) { category in
                        JunkCategoryCard(model: model, category: category)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)

            ActionBar(
                summary: model.selectedSize.formattedBytes,
                detail: "selected of \(model.totalSize.formattedBytes)",
                buttonTitle: "Clean",
                isWorking: model.isCleaning,
                isDisabled: model.selection.isEmpty
            ) {
                isConfirmingClean = true
            }
        }
        .animation(.smooth, value: model.lastResult?.removedCount)
    }
}

/// Expandable glass card for one junk category.
private struct JunkCategoryCard: View {
    let model: JunkCleanerModel
    let category: JunkCategory
    @State private var isExpanded = false

    var body: some View {
        let items = model.items(in: category)

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { model.isSelected(category) },
                    set: { model.setSelected(category, $0) }
                ))
                .labelsHidden()
                .disabled(items.isEmpty)

                IconTile(systemImage: category.systemImage, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.headline)
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                Text(items.isEmpty ? "Clean ✓" : model.size(of: category).formattedBytes)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(items.isEmpty ? 0.6 : 1))
                    .contentTransition(.numericText())

                Button {
                    withAnimation(.smooth) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.3 : 1)
            }
            .padding(14)

            if isExpanded && !items.isEmpty {
                Divider()
                    .overlay(.white.opacity(0.2))
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassPanel(cornerRadius: 18)
        .clipShape(.rect(cornerRadius: 18))
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { model.selection.contains(item.url) },
                set: { model.setSelected(item, $0) }
            )) {
                HStack {
                    FileIcon(url: item.url, size: 18)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(item.size.formattedBytes)
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .contextMenu { FileContextMenu(url: item.url) }
    }
}
