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
            // Default, recoverable choice first.
            Button("Move to Trash") {
                Task { await model.uninstallSelectedApp(permanently: false) }
            }
            Button("Delete Permanently", role: .destructive) {
                Task { await model.uninstallSelectedApp(permanently: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
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

    private var confirmationMessage: String {
        var text = "Move to Trash keeps everything recoverable until you empty the Trash. Delete Permanently frees the space right away and can’t be undone."
        if model.requiresAdmin {
            text += " macOS will ask for an administrator password because some items are system-wide."
        }
        return text
    }

    private var results: some View {
        @Bindable var bindable = model
        return VStack(spacing: 12) {
            FeatureHeader(
                title: "Uninstaller",
                subtitle: "\(model.apps.count) apps installed. Select an app to see its leftover files."
            )

            if let result = model.lastResult {
                RemovalResultBanner(result: result, movedToTrash: !model.lastRemovalWasPermanent)
            }
            if let info = model.infoMessage {
                Label(info, systemImage: "info.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(cornerRadius: 14)
                    .padding(.horizontal, 24)
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
                detail: model.selectedApp.map { app in
                    model.requiresAdmin ? "to remove from \(app.name) • requires administrator password" : "to remove from \(app.name)"
                } ?? "Select an app first",
                buttonTitle: "Uninstall",
                isWorking: model.isUninstalling,
                isDisabled: model.selectedApp == nil || model.isRunningOfficialUninstaller
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
                    // Inside the List so long notices scroll instead of growing the panel's minimum height.
                    if hasNotices {
                        Section {
                            notices(for: app)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                    }
                    Section("Application") {
                        HStack {
                            FileIcon(url: app.url, size: 18)
                            Text(app.url.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if model.analysis.appRequiresAdmin {
                                Tag(text: "Admin", systemImage: "lock.fill")
                            }
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

    private var hasNotices: Bool {
        model.isSelectedAppRunning || model.analysis.officialUninstaller != nil || model.analysis.hasSystemExtension
    }

    /// Running app, official uninstaller and system-extension hints for the selected app.
    @ViewBuilder
    private func notices(for app: InstalledApp) -> some View {
        VStack(spacing: 8) {
            if model.isSelectedAppRunning {
                noticeCard(
                    systemImage: "play.circle.fill",
                    title: "\(app.name) is running",
                    message: "Quit it before uninstalling."
                ) {
                    Button("Quit \(app.name)") { model.quitSelectedApp() }
                        .buttonStyle(.glass)
                }
            }
            if let uninstaller = model.analysis.officialUninstaller {
                noticeCard(
                    systemImage: "wand.and.stars",
                    title: "Official uninstaller available",
                    message: "Recommended for VPN, security, and driver software. It cleanly removes system extensions and background services."
                ) {
                    if model.isRunningOfficialUninstaller {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Run Official Uninstaller") {
                            Task { await model.runOfficialUninstaller() }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(model.isUninstalling)
                        .help(uninstaller.url.path(percentEncoded: false))
                    }
                }
            } else if model.analysis.hasSystemExtension {
                noticeCard(
                    systemImage: "puzzlepiece.extension.fill",
                    title: "Includes a system extension",
                    message: "Restart your Mac after uninstalling to finish removing it."
                ) { EmptyView() }
            }
        }
    }

    private func noticeCard<Accessory: View>(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(4)
            }
            Spacer()
            accessory()
        }
        .padding(12)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func leftoverRow(_ item: LeftoverItem) -> some View {
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
                        Text("\(item.kind.title) • \(item.url.deletingLastPathComponent().path(percentEncoded: false))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            if item.requiresAdmin {
                Tag(text: "Admin", systemImage: "lock.fill")
            }
            Text(item.size.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
        .contextMenu { FileContextMenu(url: item.url) }
    }
}

/// Small capsule label, e.g. "Admin".
private struct Tag: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.2), in: .capsule)
            .help("Removing this requires an administrator password")
    }
}
