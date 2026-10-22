//
//  Theme.swift
//  JoClean
//

import SwiftUI

/// Bright color palette and icon used by one module.
struct ModuleTheme: Equatable {
    /// Three colors blended by the animated mesh background.
    let colors: [Color]
    /// Tint for buttons and highlights.
    let accent: Color
    let symbol: String

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let smartScan = ModuleTheme(
        colors: [Color(red: 1.0, green: 0.30, blue: 0.62), Color(red: 0.58, green: 0.36, blue: 1.0), Color(red: 0.22, green: 0.72, blue: 1.0)],
        accent: Color(red: 1.0, green: 0.36, blue: 0.70),
        symbol: "sparkles"
    )
    static let systemJunk = ModuleTheme(
        colors: [Color(red: 1.0, green: 0.38, blue: 0.48), Color(red: 1.0, green: 0.34, blue: 0.75), Color(red: 1.0, green: 0.62, blue: 0.30)],
        accent: Color(red: 1.0, green: 0.42, blue: 0.55),
        symbol: "trash.circle.fill"
    )
    static let trash = ModuleTheme(
        colors: [Color(red: 0.10, green: 0.80, blue: 0.56), Color(red: 0.12, green: 0.70, blue: 0.88), Color(red: 0.50, green: 0.86, blue: 0.32)],
        accent: Color(red: 0.12, green: 0.78, blue: 0.62),
        symbol: "trash.fill"
    )
    static let largeFiles = ModuleTheme(
        colors: [Color(red: 1.0, green: 0.55, blue: 0.18), Color(red: 1.0, green: 0.38, blue: 0.42), Color(red: 1.0, green: 0.72, blue: 0.22)],
        accent: Color(red: 1.0, green: 0.55, blue: 0.20),
        symbol: "doc.text.magnifyingglass"
    )
    static let uninstaller = ModuleTheme(
        colors: [Color(red: 0.22, green: 0.52, blue: 1.0), Color(red: 0.16, green: 0.80, blue: 0.96), Color(red: 0.48, green: 0.42, blue: 1.0)],
        accent: Color(red: 0.25, green: 0.58, blue: 1.0),
        symbol: "xmark.app.fill"
    )
    static let malware = ModuleTheme(
        colors: [Color(red: 0.05, green: 0.78, blue: 0.78), Color(red: 0.36, green: 0.42, blue: 1.0), Color(red: 0.62, green: 0.32, blue: 0.96)],
        accent: Color(red: 0.22, green: 0.62, blue: 1.0),
        symbol: "shield.lefthalf.filled"
    )
    static let optimization = ModuleTheme(
        colors: [Color(red: 0.66, green: 0.32, blue: 1.0), Color(red: 0.96, green: 0.38, blue: 0.86), Color(red: 0.36, green: 0.48, blue: 1.0)],
        accent: Color(red: 0.72, green: 0.40, blue: 1.0),
        symbol: "gauge.with.dots.needle.67percent"
    )
}

extension EnvironmentValues {
    /// Theme of the module currently on screen; shared views read it for tinting.
    @Entry var moduleTheme: ModuleTheme = .smartScan
}

/// Full-window mesh gradient whose control points drift slowly, giving the app a "living" background.
struct AnimatedMeshBackground: View {
    let theme: ModuleTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        // 20 fps is plenty for a slow drift; pausing while the window is in the background saves CPU/GPU.
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || !appearsActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: Self.points(at: time), colors: meshColors)
        }
        // A soft dark fade at the bottom keeps white text readable on the brightest colors.
        .overlay(
            LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
        )
        .ignoresSafeArea()
    }

    private var meshColors: [Color] {
        let c = theme.colors
        return [
            c[0], c[1], c[2],
            c[1], c[2], c[0],
            c[2], c[0], c[1]
        ]
    }

    /// Corner points stay fixed; edge and center points oscillate on independent sine waves.
    private static func points(at time: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ amplitude: Double, _ phase: Double = 0) -> Float {
            Float(sin(time * speed + phase) * amplitude)
        }
        return [
            [0, 0], [0.5 + wave(0.35, 0.18), 0], [1, 0],
            [0, 0.5 + wave(0.30, 0.18, 1)], [0.5 + wave(0.25, 0.22, 2), 0.5 + wave(0.32, 0.22, 3)], [1, 0.5 + wave(0.40, 0.18, 4)],
            [0, 1], [0.5 + wave(0.28, 0.18, 5), 1], [1, 1]
        ]
    }
}

/// Glass panel used for cards and lists on top of the gradient.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            // A light white tint keeps the glass bright on the colorful background.
            .glassEffect(.regular.tint(.white.opacity(0.24)), in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// Makes a List or Table transparent so it can sit on a glass panel.
    func transparentScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(.clear)
    }
}

/// Slight shrink when pressed.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}
