//
//  make_infographic.swift
//  Renders docs/infographic.png with SwiftUI.
//
//  Usage:
//    swiftc -o /tmp/make_infographic docs/make_infographic.swift
//    /tmp/make_infographic JoClean/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png /tmp/infographic@2x.png
//    sips --resampleWidth 1600 /tmp/infographic@2x.png --out docs/infographic.png
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Palette (same module themes as the app)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

struct Theme {
    let colors: [Color]
    let symbol: String
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

let smartScan = Theme(colors: [rgb(1.0, 0.30, 0.62), rgb(0.58, 0.36, 1.0), rgb(0.22, 0.72, 1.0)], symbol: "sparkles")
let systemJunk = Theme(colors: [rgb(1.0, 0.38, 0.48), rgb(1.0, 0.34, 0.75), rgb(1.0, 0.62, 0.30)], symbol: "trash.circle.fill")
let trash = Theme(colors: [rgb(0.10, 0.80, 0.56), rgb(0.12, 0.70, 0.88), rgb(0.50, 0.86, 0.32)], symbol: "trash.fill")
let largeFiles = Theme(colors: [rgb(1.0, 0.55, 0.18), rgb(1.0, 0.38, 0.42), rgb(1.0, 0.72, 0.22)], symbol: "doc.text.magnifyingglass")
let uninstaller = Theme(colors: [rgb(0.22, 0.52, 1.0), rgb(0.16, 0.80, 0.96), rgb(0.48, 0.42, 1.0)], symbol: "xmark.app.fill")
let optimization = Theme(colors: [rgb(0.66, 0.32, 1.0), rgb(0.96, 0.38, 0.86), rgb(0.36, 0.48, 1.0)], symbol: "gauge.with.dots.needle.67percent")
let malware = Theme(colors: [rgb(0.05, 0.78, 0.78), rgb(0.36, 0.42, 1.0), rgb(0.62, 0.32, 0.96)], symbol: "shield.lefthalf.filled")
let menuBar = Theme(colors: [rgb(0.16, 0.48, 0.98), rgb(0.12, 0.66, 0.90), rgb(0.33, 0.36, 0.96)], symbol: "menubar.rectangle")

let ink = rgb(0.13, 0.11, 0.27)          // dark text on the light canvas
let inkSoft = rgb(0.38, 0.36, 0.52)

// MARK: - Building blocks

struct Feature {
    let number: Int
    let title: String
    let tagline: String
    let theme: Theme
    let points: [String]
}

let features: [Feature] = [
    Feature(number: 1, title: "Smart Scan", tagline: "Your Mac at a glance", theme: smartScan, points: [
        "Live Disk, Memory & CPU dashboard",
        "One-click scan of system junk and the Trash",
        "See exactly how much space you can reclaim"
    ]),
    Feature(number: 2, title: "System Junk", tagline: "Clear the clutter", theme: systemJunk, points: [
        "User caches and old logs",
        "Xcode DerivedData, DeviceSupport & Simulator caches",
        "Leftover installers (.dmg, .pkg, .xip)"
    ]),
    Feature(number: 3, title: "Trash", tagline: "Free the space for real", theme: trash, points: [
        "See what's taking up room in the Trash",
        "Empty it permanently in one click",
        "Works through Finder, even without Full Disk Access"
    ]),
    Feature(number: 4, title: "Large & Old Files", tagline: "Find forgotten space hogs", theme: largeFiles, points: [
        "Big or long-untouched files, anywhere",
        "Size (50 MB – 5 GB) and age filters",
        "Sortable table with Show in Finder"
    ]),
    Feature(number: 5, title: "Uninstaller", tagline: "Remove apps completely", theme: uninstaller, points: [
        "Apps plus leftovers in ~/Library and /Library",
        "System-wide apps via the macOS admin prompt",
        "Runs official vendor uninstallers (VPN, security)",
        "Move to Trash or Delete Permanently"
    ]),
    Feature(number: 6, title: "Optimization", tagline: "Keep things snappy", theme: optimization, points: [
        "Running apps ranked by memory use",
        "Quit or Force Quit in one click",
        "Manage Launch Agents that start at login"
    ]),
    Feature(number: 7, title: "Malware Check", tagline: "No account. No API key.", theme: malware, points: [
        "Apple XProtect signatures, scanned locally",
        "Gatekeeper signing & notarization check",
        "CIRCL known-file lookup, optional VirusTotal",
        "Only file hashes ever leave your Mac"
    ]),
    Feature(number: 8, title: "Menu Bar", tagline: "Stats, always one click away", theme: menuBar, points: [
        "Disk, Memory & CPU in your menu bar",
        "Open JoClean or quit from anywhere",
        "Updates live every 2 seconds"
    ])
]

struct IconBadge: View {
    let symbol: String
    let size: CGFloat
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(0.22), in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
    }
}

struct FeatureCard: View {
    let feature: Feature
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                IconBadge(symbol: feature.theme.symbol, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text(feature.tagline)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .opacity(0.9)
                }
                Spacer()
                Text(String(format: "%02d", feature.number))
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .opacity(0.22)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(feature.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .bold))
                        Text(point)
                            .font(.system(size: 21, weight: .medium, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
        .padding(28)
        .frame(width: 740, height: 330, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous).fill(feature.theme.gradient)
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                // Soft highlight for depth
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 520))
                // Big faint symbol watermark
                Image(systemName: feature.theme.symbol)
                    .font(.system(size: 210, weight: .bold))
                    .foregroundStyle(.white.opacity(0.10))
                    .offset(x: 250, y: 70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .shadow(color: feature.theme.colors[1].opacity(0.35), radius: 24, y: 14)
    }
}

struct SectionTitle: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(smartScan.gradient)
            Text(title)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
        }
    }
}

struct EngineChip: View {
    let symbol: String
    let name: String
    let detail: String
    let badge: String
    let badgeColor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(malware.gradient)
                Spacer()
                Text(badge)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(badgeColor, in: .capsule)
            }
            Text(name)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
            Text(detail)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 357, height: 230, alignment: .topLeading)
        .background(.white, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(malware.colors[1].opacity(0.18), lineWidth: 2))
        .shadow(color: malware.colors[1].opacity(0.12), radius: 16, y: 8)
    }
}

struct SafetyItem: View {
    let symbol: String
    let title: String
    let detail: String
    let theme: Theme
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(theme.gradient, in: .rect(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 740, height: 150, alignment: .topLeading)
        .background(.white, in: .rect(cornerRadius: 26, style: .continuous))
        .shadow(color: theme.colors[0].opacity(0.12), radius: 14, y: 8)
    }
}

struct Pill: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.white.opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
    }
}

// MARK: - Infographic

struct Infographic: View {
    let icon: NSImage?

    var body: some View {
        VStack(spacing: 70) {
            header
            VStack(spacing: 40) {
                SectionTitle(eyebrow: "Everything in one app", title: "8 tools to keep your Mac clean & safe")
                let rows = stride(from: 0, to: features.count, by: 2).map { Array(features[$0..<min($0 + 2, features.count)]) }
                VStack(spacing: 40) {
                    ForEach(0..<rows.count, id: \.self) { index in
                        HStack(spacing: 40) {
                            ForEach(rows[index], id: \.number) { FeatureCard(feature: $0) }
                        }
                    }
                }
            }
            engines
            safety
            footer
        }
        .padding(.top, 0)
        .padding(.bottom, 70)
        .frame(width: 1600)
        .background(
            LinearGradient(colors: [rgb(0.97, 0.96, 1.0), rgb(0.93, 0.95, 1.0), rgb(1.0, 0.95, 0.98)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var header: some View {
        ZStack {
            LinearGradient(colors: smartScan.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: 700)
            // Decorative sparkles
            ForEach(Array([(CGPoint(x: 1380, y: 90), 70.0), (CGPoint(x: 1480, y: 200), 40.0), (CGPoint(x: 120, y: 420), 46.0), (CGPoint(x: 1300, y: 430), 30.0)].enumerated()), id: \.offset) { _, item in
                Image(systemName: "sparkle")
                    .font(.system(size: item.1, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .white, radius: 12)
                    .position(item.0)
            }

            VStack(spacing: 26) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 230, height: 230)
                        .shadow(color: .black.opacity(0.25), radius: 26, y: 16)
                }
                Text("JoClean")
                    .font(.system(size: 112, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                Text("The colorful all-in-one Mac cleaner & malware checker")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                HStack(spacing: 14) {
                    Pill(symbol: "swift", text: "Native SwiftUI")
                    Pill(symbol: "cpu", text: "Apple Silicon + Intel")
                    Pill(symbol: "apple.logo", text: "macOS 26.6+")
                    Pill(symbol: "lock.shield.fill", text: "Privacy-first")
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 70)
        }
        .frame(width: 1600, height: 720)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 70, bottomTrailingRadius: 70, style: .continuous))
    }

    private var engines: some View {
        VStack(spacing: 34) {
            SectionTitle(eyebrow: "Malware Check", title: "Four engines, zero sign-up")
            HStack(spacing: 24) {
                EngineChip(symbol: "shield.lefthalf.filled", name: "XProtect", detail: "Apple's own malware signatures, run locally with libyara.", badge: "LOCAL", badgeColor: rgb(0.10, 0.72, 0.52))
                EngineChip(symbol: "checkmark.seal.fill", name: "Gatekeeper", detail: "Code signing & Apple notarization for apps, DMGs, installers.", badge: "LOCAL", badgeColor: rgb(0.10, 0.72, 0.52))
                EngineChip(symbol: "externaldrive.badge.checkmark", name: "CIRCL", detail: "Billions of known legitimate files. Sends a hash only.", badge: "ONLINE", badgeColor: rgb(0.30, 0.45, 1.0))
                EngineChip(symbol: "network.badge.shield.half.filled", name: "VirusTotal", detail: "70+ antivirus engines with your own free API key.", badge: "OPTIONAL", badgeColor: rgb(0.62, 0.32, 0.96))
            }
            Label("File contents are never uploaded — only SHA-256 fingerprints.", systemImage: "lock.fill")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(inkSoft)
        }
    }

    private var safety: some View {
        VStack(spacing: 34) {
            SectionTitle(eyebrow: "Safety first", title: "Powerful, but careful")
            VStack(spacing: 24) {
                HStack(spacing: 40) {
                    SafetyItem(symbol: "hand.tap.fill", title: "You're in control", detail: "Nothing is scanned until you click Scan, and every destructive action asks first.", theme: smartScan)
                    SafetyItem(symbol: "arrow.uturn.backward.circle.fill", title: "Recoverable by default", detail: "Cleaned items go to the Trash. Delete Permanently only when you choose it.", theme: trash)
                }
                HStack(spacing: 40) {
                    SafetyItem(symbol: "key.fill", title: "Admin only when needed", detail: "System-wide removals use macOS's own password prompt. JoClean never sees it.", theme: uninstaller)
                    SafetyItem(symbol: "lock.shield.fill", title: "System folders protected", detail: "/System, /Library, /Applications and ~/Library themselves can never be removed.", theme: largeFiles)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download JoClean 1.1.2")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                    Text("github.com/linggameidianza/JoClean")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(smartScan.gradient)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 22)
            .background(.white, in: .capsule)
            .shadow(color: smartScan.colors[1].opacity(0.18), radius: 20, y: 10)

            Text("Free • Universal app for Apple Silicon & Intel • Requires macOS 26.6 or later")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(inkSoft)
        }
    }
}

// MARK: - Render

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    let iconPath = args.count > 1 ? args[1] : ""
    let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "JoClean-Infographic.png")
    let icon = NSImage(contentsOfFile: iconPath)

    let renderer = ImageRenderer(content: Infographic(icon: icon))
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: 1600, height: nil)
    guard let image = renderer.cgImage,
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Render failed")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("Wrote \(output.path) \(image.width)x\(image.height)")
}
