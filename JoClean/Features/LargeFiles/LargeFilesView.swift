//
//  LargeFilesView.swift
//  JoClean
//

import SwiftUI
import UniformTypeIdentifiers

struct LargeFilesView: View {
    @Environment(AppState.self) private var appState
    @State private var isChoosingFolder = false
    @State private var isConfirmingRemove = false

    private var model: LargeFilesModel { appState.largeFiles }

    private enum Phase: Hashable { case welcome, scanning, empty, results }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        if !model.hasScanned { return .welcome }
        return model.files.isEmpty ? .empty : .results
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 24)
                .padding(.top, 12)

            ZStack {
                switch phase {
                case .welcome:
                    ScanPromptView(
                        title: "Large & Old Files",
                        message: "Find large files and files you haven’t opened in a long time in \(model.rootURL.lastPathComponent)."
                    ) {
                        model.scan()
                    }
                    .transition(.blurReplace)
                case .scanning:
                    ScanningView(
                        message: "Scanning \(model.rootURL.lastPathComponent)…\nThis can take a few minutes.",
                        cancelAction: { model.cancelScan() }
                    )
                    .transition(.blurReplace)
                case .empty:
                    CompletionView(
                        title: "No Large Files",
                        message: "No files match your filters.",
                        buttonTitle: "Scan Again"
                    ) {
                        model.scan()
                    }
                    .transition(.blurReplace)
                case .results:
                    results
                        .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.5), value: phase)
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.rootURL = url
            }
        }
        .confirmationDialog(
            "Move \(model.selection.count) files (\(model.selectedSize.formattedBytes)) to the Trash?",
            isPresented: $isConfirmingRemove
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.removeSelected() }
            }
        } message: {
            Text("Make sure you no longer need these files.")
        }
    }

    private var filterBar: some View {
        @Bindable var bindable = model
        return HStack(spacing: 14) {
            Button {
                isChoosingFolder = true
            } label: {
                Label(model.rootURL.lastPathComponent, systemImage: "folder.fill")
            }
            .buttonStyle(.glass)
            .help(model.rootURL.path(percentEncoded: false))

            Picker("Size", selection: $bindable.minimumSizeMB) {
                Text("≥ 50 MB").tag(50)
                Text("≥ 100 MB").tag(100)
                Text("≥ 500 MB").tag(500)
                Text("≥ 1 GB").tag(1_000)
                Text("≥ 5 GB").tag(5_000)
            }
            .fixedSize()

            Picker("Age", selection: $bindable.ageFilter) {
                ForEach(FileAgeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .fixedSize()

            Spacer()

            if model.hasScanned {
                Button("Scan", systemImage: "magnifyingglass") {
                    model.scan()
                }
                .buttonStyle(.glass)
                .disabled(model.isScanning)
            }
        }
        .padding(10)
        .glassPanel(cornerRadius: 16)
    }

    private var results: some View {
        @Bindable var bindable = model
        return VStack(spacing: 12) {
            FeatureHeader(
                title: "Large & Old Files",
                subtitle: "\(model.files.count) files found • \(model.totalSize.formattedBytes) total. Select files to remove."
            )

            if let result = model.lastResult {
                RemovalResultBanner(result: result)
            }

            Table(model.sortedFiles, selection: $bindable.selection, sortOrder: $bindable.sortOrder) {
                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 10) {
                        FileIcon(url: file.url, size: 22)
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .lineLimit(1)
                            Text(file.folder)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .contextMenu { FileContextMenu(url: file.url) }
                }
                TableColumn("Kind", value: \.kind)
                    .width(60)
                TableColumn("Size", value: \.size) { file in
                    Text(file.size.formattedBytes)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .width(90)
                TableColumn("Modified", value: \.modifiedSortKey) { file in
                    Text(file.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                }
                .width(110)
                TableColumn("Last Opened", value: \.lastOpenedSortKey) { file in
                    Text(file.lastOpened?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                }
                .width(110)
            }
            .transparentScrollBackground()
            .padding(6)
            .glassPanel()
            .padding(.horizontal, 24)

            ActionBar(
                summary: model.selectedSize.formattedBytes,
                detail: model.selection.isEmpty ? "Select files in the table" : "\(model.selection.count) files selected",
                buttonTitle: "Remove",
                isWorking: model.isRemoving,
                isDisabled: model.selection.isEmpty
            ) {
                isConfirmingRemove = true
            }
        }
        .animation(.smooth, value: model.lastResult?.removedCount)
    }
}
