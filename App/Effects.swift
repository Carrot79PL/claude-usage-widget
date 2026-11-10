import AppKit
import SwiftUI

// MARK: - Tryb wyglądu

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let storageKey = "appearance"

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Jasny"
        case .dark: "Ciemny"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    func apply() { NSApp.appearance = nsAppearance }
}

/// Segmentowy przełącznik Auto / Jasny / Ciemny w szklanej kapsule.
struct AppearancePicker: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppearanceMode.allCases) { m in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { mode = m }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .symbolEffect(.bounce, value: mode == m)
                        Text(m.title).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .foregroundStyle(mode == m ? Color.primary : Color.secondary)
                    .background {
                        if mode == m {
                            Capsule()
                                .fill(.background.opacity(0.85))
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "selected", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Wygląd: \(m.title)")
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
        .onChange(of: mode, initial: true) { _, m in
            // płynne przejście całego okna między trybami
            if let w = NSApp.keyWindow ?? NSApp.windows.first, let view = w.contentView {
                let t = CATransition(); t.type = .fade; t.duration = 0.35
                view.layer?.add(t, forKey: "appearance")
            }
            m.apply()
        }
    }
}

// MARK: - Szkło

extension View {
    /// Powierzchnia z Liquid Glass (macOS 26+), opcjonalnie lekko zabarwiona.
    func glassSurface(_ radius: CGFloat = 18, tint: Color? = nil) -> some View {
        glassEffect(.regular.tint(tint?.opacity(0.10)), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Przechylanie 3D za kursorem z odblaskiem.
    func tilt3D(_ radius: CGFloat = 16, maxAngle: Double = 6, shine: Bool = true) -> some View {
        modifier(Tilt3D(radius: radius, maxAngle: maxAngle, shine: shine))
    }

    /// Wjazd elementu z opóźnieniem (fade + przesunięcie + rozmycie).
    func appearIn(delay: Double) -> some View { modifier(AppearIn(delay: delay)) }
}

/// Półprzezroczyste tło z kolorowych plam — za nim prześwituje pulpit.
/// Statyczne: animowane tło zmuszało szkło do ponownego rozmywania całego okna w każdej klatce.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let a: Float = 0.5
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + 0.12 * a, 0], [1, 0],
                [0, 0.45 + 0.15 * a], [0.55 - 0.15 * a, 0.5 + 0.1 * a], [1, 0.55 - 0.15 * a],
                [0, 1], [0.45 + 0.15 * a, 1], [1, 1],
            ],
            colors: [
                Palette.claude, .clear, Palette.violet,
                .clear, Palette.blue.opacity(0.35), .clear,
                Palette.teal, .clear, Palette.coral,
            ]
        )
        .opacity(scheme == .dark ? 0.30 : 0.22)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .drawingGroup()
    }
}

struct Tilt3D: ViewModifier {
    let radius: CGFloat
    let maxAngle: Double
    let shine: Bool
    @State private var p: CGPoint? = nil   // pozycja kursora: -0.5…0.5
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let x = p?.x ?? 0, y = p?.y ?? 0
        content
            .overlay {
                if shine, p != nil {
                    RadialGradient(colors: [.white.opacity(0.28), .clear],
                                   center: UnitPoint(x: x + 0.5, y: y + 0.5),
                                   startRadius: 0, endRadius: max(size.width, size.height) * 0.75)
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(-y * maxAngle * 2), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(x * maxAngle * 2), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .scaleEffect(p == nil ? 1 : 1.02)
            .zIndex(p == nil ? 0 : 1)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    switch phase {
                    case .active(let l) where size.width > 0 && size.height > 0:
                        p = CGPoint(x: l.x / size.width - 0.5, y: l.y / size.height - 0.5)
                    default:
                        p = nil
                    }
                }
            }
    }
}

struct AppearIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

/// Pionowy stos strony — każdy element wjeżdża kolejno (kaskada).
struct PageStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { i, sub in
                    sub.appearIn(delay: min(0.3, 0.04 + 0.05 * Double(i)))
                }
            }
        }
    }
}

// MARK: - Rozbłysk Claude (2D i „3D”)

/// Promienisty rozbłysk w stylu Claude — ten sam motyw co ikona aplikacji.
struct ClaudeBurst: View {
    var color: Color = Palette.claude
    private static let lens: [CGFloat] = [1.0, 0.86, 0.95, 0.80, 1.0, 0.90, 0.84, 0.97, 0.88, 1.0, 0.82, 0.93]

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                ForEach(0..<Self.lens.count, id: \.self) { i in
                    VStack(spacing: 0) {
                        Capsule().fill(color)
                            .frame(width: s * (i % 3 == 0 ? 0.13 : 0.11), height: s * 0.475 * Self.lens[i])
                        Spacer(minLength: 0)
                    }
                    .frame(width: s * 0.15, height: s)
                    .rotationEffect(.degrees(Double(i) * 30 + (i % 2 == 0 ? 2 : -3)))
                }
                Circle().fill(color).frame(width: s * 0.275)
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Wytłoczony, unoszący się i kołyszący w 3D rozbłysk (do nagłówków).
struct FloatingBurst: View {
    var size: CGFloat = 110
    var face: Color = .white
    var side: Color = Color(red: 0.62, green: 0.25, blue: 0.20)
    @State private var spin = false
    @State private var wobble = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            // cień na „podłodze”
            Ellipse().fill(.black.opacity(0.22))
                .frame(width: size * 0.7, height: size * 0.12)
                .blur(radius: 7)
                .offset(y: size * 0.62)
                .scaleEffect(wobble ? 0.85 : 1)
            ZStack {
                // grubość bryły: kilka warstw przesuniętych w głąb
                ForEach((1...4).reversed(), id: \.self) { k in
                    ClaudeBurst(color: side.opacity(0.55 + 0.08 * Double(4 - k)))
                        .offset(x: CGFloat(k) * 1.2, y: CGFloat(k) * 1.9)
                }
                ClaudeBurst(color: face)
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.0), .black.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .mask(ClaudeBurst(color: .white))
                    )
            }
            .rotationEffect(.degrees(spin ? 360 : 0))
            .rotation3DEffect(.degrees(wobble ? 24 : -18), axis: (x: 1, y: 0.8, z: 0), perspective: 0.55)
            .offset(y: wobble ? -6 : 4)
        }
        .frame(width: size, height: size)
        .drawingGroup()   // jedna warstwa rysowana przez GPU zamiast ~100 osobnych kształtów
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            // animuje się tylko pod kursorem — w spoczynku nie zużywa procesora
            if h {
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { spin = true }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { wobble = true }
            } else {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { spin = false; wobble = false }
            }
        }
        .help("Najedź, aby ożywić")
    }
}

// MARK: - Liczby i ikony

/// Procent, który „odlicza się” w górę razem z animacją pierścienia.
struct CountingPercent: View, Animatable {
    var value: Double
    var font: Font

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Fmt.percent(value)).font(font).monospacedDigit()
    }
}

/// Błyszcząca ikona-kafelek z połyskiem i cieniem (efekt wypukłości).
struct GlossyIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26
    var radius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(tint.gradient)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.0)],
                                              startPoint: .top, endPoint: .center))
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                }
            }
            .shadow(color: tint.opacity(0.45), radius: size * 0.16, y: size * 0.09)
    }
}
