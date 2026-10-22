//
//  UninstallerView.swift
//  JoClean
//

import SwiftUI

struct UninstallerView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var isConfirmingUninstall = false

    private var model: UninstallerModel { appState.uninstaller }

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedStandardContains(searchText) }
    }

    private enum Phase: Hashable { case welcome, loading, results }

    private var phase: Phase {
        if model.isLoading { return .loading }
        return model.hasLoaded ? .results : .welcome
    }

    var body: some View {
        ZStack {
            switch phase {
            case .welcome:
                ScanPromptView(
                    title: "Uninstaller",
                    message: "Completely remove apps you don’t use, along with all their leftover files.",
                    buttonTitle: "View Apps"
                ) {
                    Task { await model.loadApps() }
                }
                .transition(.blurReplace)
            case .loading:
                ScanningView(message: "Gathering the list of apps…")
                    .transition(.blurReplace)
            case .results:
                results
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.5), value: phase)
        .toolbar {
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await model.loadApps() }
                }
                .disabled(model.isLoading)
            }
        }
        .confirmationDialog(
            "Uninstall \(model.selectedApp?.name ?? "app") (\(model.totalUninstallSize.formattedBytes))?",
            isPresented: $isConfirmingUninstall
        ) {
            Button("Uninstall App", role: .destructive) {
                Task { await model.uninstallSelectedApp() }
            }
        } message: {
            Text("The app and the selected leftover files will be moved to the Trash.")
        }
        .alert(
            "Couldn’t Uninstall",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var results: some View {
        @Bindable var bindable = model
        return VStack(spacing: 12) {
            FeatureHeader(
                title: "Uninstaller",
                subtitle: "\(model.apps.count) apps installed. Select an app to see its leftover files."
            )

            if let result = model.lastResult {
                RemovalResultBanner(result: result)
            }

            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("Search apps", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 10))
                    .padding(10)

                    List(filteredApps, selection: $bindable.selectedAppID) { app in
                        HStack(spacing: 10) {
                            FileIcon(url: app.url, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .lineLimit(1)
                                Text(app.size.formattedBytes)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 3)
                        .listRowBackground(Color.clear)
                    }
                    .transparentScrollBackground()
                }
                .frame(width: 280)
                .glassPanel()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel()
            }
            .padding(.horizontal, 24)

            ActionBar(
                summary: model.selectedApp == nil ? "—" : model.totalUninstallSize.formattedBytes,
                detail: model.selectedApp.map { "to remove from \($0.name)" } ?? "Select an app first",
                buttonTitle: "Uninstall",
                isWorking: model.isUninstalling,
                isDisabled: model.selectedApp == nil
            ) {
                isConfirmingUninstall = true
            }
        }
        .animation(.smooth, value: model.selectedAppID)
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    FileIcon(url: app.url, size: 72)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.title2.bold())
                        if let version = app.version {
                            Text("Version \(version)")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text(app.bundleIdentifier ?? "No bundle identifier")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(18)
                .id(app.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

                List {
                    Section("Application") {
                        HStack {
                            Image(systemName: "app.fill")
                            Text(app.url.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(app.size.formattedBytes)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .listRowBackground(Color.clear)
                        .contextMenu { FileContextMenu(url: app.url) }
                    }

                    Section("Leftover Files") {
                        if model.isLoadingLeftovers {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                        } else if model.leftovers.isEmpty {
                            Text("No leftover files found.")
                                .foregroundStyle(.white.opacity(0.7))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(model.leftovers) { item in
                                leftoverRow(item)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .transparentScrollBackground()
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "hand.point.left.fill")
                    .font(.system(size: 44))
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)))
                Text("Select an App")
                    .font(.title2.bold())
                Text("Select an app on the left to see its size and leftover files.")
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func leftoverRow(_ item: CleanupItem) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { model.leftoverSelection.contains(item.url) },
                set: { selected in
                    if selected {
                        model.leftoverSelection.insert(item.url)
                    } else {
                        model.leftoverSelection.remove(item.url)
                    }
                }
            )) {
                HStack {
                    FileIcon(url: item.url, size: 18)
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            Text(item.size.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
        .contextMenu { FileContextMenu(url: item.url) }
    }
}
