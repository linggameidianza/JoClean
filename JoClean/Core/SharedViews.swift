//
//  SharedViews.swift
//  JoClean
//

import SwiftUI
import AppKit

/// Module title shown at the top-left, white on the gradient.
struct FeatureHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// Large floating module icon inside a glowing glass orb.
struct HeroIcon: View {
    var systemImage: String?
    var size: CGFloat = 190
    @Environment(\.moduleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    private var isAnimating: Bool { !reduceMotion && appearsActive }

    var body: some View {
        // Time-driven bobbing so it can pause when the window is inactive (phaseAnimator can't).
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            orb
                .offset(y: isAnimating ? sin(time * 2 * .pi / 4.8) * 8 : 0)
        }
    }

    private var orb: some View {
        ZStack {
            // Soft glow; a radial gradient is much cheaper to render than a large blur.
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.28), .white.opacity(0)],
                    center: .center,
                    startRadius: size * 0.4,
                    endRadius: size * 0.65
                ))
                .frame(width: size * 1.3, height: size * 1.3)
            Image(systemName: systemImage ?? theme.symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.breathe, isActive: isAnimating)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .frame(width: size, height: size)
                // Bright frosted orb: white gradient fill with a light rim.
                .background {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                }
                .shadow(color: .black.opacity(0.12), radius: 24, y: 14)
        }
    }
}

/// Hero diameter that fits the available height after reserving room for text and buttons.
/// Keeps every state screen usable in small windows instead of pushing the button off-screen.
private func adaptiveHeroSize(height: CGFloat, reserved: CGFloat, maximum: CGFloat = 190) -> CGFloat {
    // The orb's glow is 1.3× its diameter, so divide the free space by that.
    min(maximum, max(72, (height - reserved) / 1.3))
}

/// Welcome state of a module: floating icon, title, message, and a round action button.
struct ScanPromptView: View {
    let title: String
    let message: String
    var systemImage: String?
    var buttonTitle = "Scan"
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let hero = adaptiveHeroSize(height: proxy.size.height, reserved: 300)
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                HeroIcon(systemImage: systemImage, size: hero)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: 480)
                }
                Spacer(minLength: 8)
                RoundActionButton(title: buttonTitle, action: action)
                    .padding(.bottom, 24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal)
    }
}

/// Scanning state: the module icon wrapped in a spinning light ring.
struct ScanningView: View {
    let message: String
    var systemImage: String?
    var cancelAction: (() -> Void)?
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        GeometryReader { proxy in
            let reserved: CGFloat = cancelAction == nil ? 160 : 290
            let hero = adaptiveHeroSize(height: proxy.size.height, reserved: reserved, maximum: 170)
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                ZStack {
                    HeroIcon(systemImage: systemImage, size: hero)
                    // Time-driven spinner so it stops when the window is inactive.
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !appearsActive)) { context in
                        let angle = context.date.timeIntervalSinceReferenceDate / 1.1 * 360
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(
                                AngularGradient(colors: [.white.opacity(0), .white], center: .center),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: hero * 1.26, height: hero * 1.26)
                            .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
                    }
                }

                Text(message)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 460)
                Spacer(minLength: 8)
                if let cancelAction {
                    RoundActionButton(title: "Stop", action: cancelAction)
                        .padding(.bottom, 24)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal)
    }
}

/// Success state after cleaning.
struct CompletionView: View {
    let title: String
    let message: String
    var buttonTitle = "Done"
    let action: () -> Void
    @State private var didAppear = false

    var body: some View {
        GeometryReader { proxy in
            let hero = adaptiveHeroSize(height: proxy.size.height, reserved: 310)
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                HeroIcon(systemImage: "checkmark.circle.fill", size: hero)
                    .scaleEffect(didAppear ? 1 : 0.6)
                    .opacity(didAppear ? 1 : 0)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 480)
                }
                Spacer(minLength: 8)
                RoundActionButton(title: buttonTitle, action: action)
                    .padding(.bottom, 24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.45)) { didAppear = true }
        }
    }
}

/// CleanMyMac-style circular primary button with pulsing halo rings.
struct RoundActionButton: View {
    let title: String
    var isWorking = false
    var isDisabled = false
    var diameter: CGFloat = 104
    let action: () -> Void

    @Environment(\.moduleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    private var showsPulse: Bool { !isWorking && !isDisabled && !reduceMotion && appearsActive }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Halo rings expand and fade on a 2.2 s loop, offset by half a cycle.
                // Driven by time (not repeatForever) so they stop completely when not needed.
                if showsPulse {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let time = context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<2, id: \.self) { ring in
                                let progress = (time / 2.2 + Double(ring) * 0.5).truncatingRemainder(dividingBy: 1)
                                let eased = 1 - pow(1 - progress, 2)
                                Circle()
                                    .stroke(.white.opacity(0.6), lineWidth: 2)
                                    .scaleEffect(1 + 0.55 * eased)
                                    .opacity(0.8 * (1 - eased))
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Group {
                    if isWorking {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        // Font scales with the button and shrinks further if a long word doesn't fit.
                        Text(title)
                            .font(.system(size: diameter * 0.18, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, diameter * 0.1)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(theme.accent.opacity(0.55)).interactive(), in: .circle)
                .shadow(color: theme.accent.opacity(0.5), radius: 18, y: 8)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isDisabled || isWorking)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

/// Bottom area with a round action button and a large selection summary beside it.
struct ActionBar: View {
    let summary: String
    var detail: String?
    let buttonTitle: String
    let isWorking: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Spacer()
            RoundActionButton(title: buttonTitle, isWorking: isWorking, isDisabled: isDisabled, diameter: 100, action: action)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(minWidth: 180, alignment: .leading)
            Spacer()
        }
        .padding(.vertical, 22)
    }
}

/// Floating toast summarising a finished cleaning operation.
struct RemovalResultBanner: View {
    let result: RemovalResult
    var movedToTrash = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: result.removedCount)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.removedCount) items cleaned • \(result.removedBytes.formattedBytes)")
                    .font(.headline)
                if movedToTrash {
                    Text("Moved to the Trash. Empty the Trash to fully free up the space.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if !result.failures.isEmpty {
                    Text("\(result.failures.count) items couldn’t be removed (in use or administrator permission required).")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Explains how to grant Full Disk Access, which some folders require.
struct FullDiskAccessHint: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
            Text("Some folders couldn’t be read. Grant Full Disk Access so JoClean can scan everything.")
                .font(.callout)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glass)
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
        .padding(.horizontal, 24)
    }
}

/// Small glass icon tile used in list rows.
struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(0.2), in: .rect(cornerRadius: size * 0.28))
    }
}

/// Context menu actions shared by file rows.
struct FileContextMenu: View {
    let url: URL

    var body: some View {
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
        }
    }
}

/// File icon from the system.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
            .resizable()
            .frame(width: size, height: size)
    }
}

#Preview("Round buttons") {
    HStack(spacing: 40) {
        RoundActionButton(title: "Clean", diameter: 100) {}
        RoundActionButton(title: "Clean") {}
        RoundActionButton(title: "Empty", diameter: 100) {}
        RoundActionButton(title: "View Apps") {}
    }
    .padding(60)
    .background(ModuleTheme.systemJunk.gradient)
    .environment(\.moduleTheme, .systemJunk)
    .environment(\.colorScheme, .dark)
}
