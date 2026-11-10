import SwiftUI

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let coral = Color(red: 0.94, green: 0.36, blue: 0.40)
    static let amber = Color(red: 0.96, green: 0.65, blue: 0.20)
    static let teal = Color(red: 0.13, green: 0.66, blue: 0.62)
    static let mint = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let blue = Color(red: 0.25, green: 0.52, blue: 0.95)
    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.90)
    static let violet = Color(red: 0.58, green: 0.38, blue: 0.90)
    static let pink = Color(red: 0.90, green: 0.35, blue: 0.65)
    static let slate = Color(red: 0.45, green: 0.50, blue: 0.58)

    static func gradient(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let claudeGradient = gradient(claude, coral)
}

/// Karta z tytułem, ikoną i treścią.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Palette.claude
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let icon {
                    GlossyIcon(symbol: icon, tint: tint, size: 26, radius: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let info = Explain.card[title] {
                    InfoButton(text: info, size: 15)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassSurface(20)
    }
}

/// Kolorowy kafelek z liczbą (KPI).
struct KPITile: View {
    let title: String
    let value: String
    var detail: String = ""
    let icon: String
    let colors: (Color, Color)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if let info = Explain.tile[title] {
                    InfoButton(text: info, size: 12).foregroundStyle(.white.opacity(0.8)).environment(\.colorScheme, .dark)
                }
            }
            .opacity(0.92)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
            Text(detail.isEmpty ? " " : detail)
                .font(.system(size: 12)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.gradient(colors.0, colors.1))
                // połysk szkła na górnej połowie
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center))
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white.opacity(0.10))
                    .offset(x: 10, y: -6)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: colors.0.opacity(0.40), radius: 12, y: 6)
        )
        .tilt3D(16)
    }
}

/// Pierścień z procentem — wypełnia się animacją, ma połysk i głębię.
struct RingGauge: View {
    let percent: Double
    var size: CGFloat = 120
    var lineWidth: CGFloat = 13
    var label: String? = nil
    @State private var shown: Double = 0

    var body: some View {
        let c = Fmt.color(percent)
        let frac = min(shown, 100) / 100
        ZStack {
            // wgłębiony tor
            Circle().stroke(c.opacity(0.14), lineWidth: lineWidth)
            Circle().stroke(.black.opacity(0.10), lineWidth: 1)
                .frame(width: size - lineWidth, height: size - lineWidth)
                .blur(radius: 0.6)
            // kopułka w środku
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.22), c.opacity(0.06), .clear],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.45))
                .padding(lineWidth * 1.2)
            // łuk
            Circle()
                .trim(from: 0, to: frac)
                .stroke(AngularGradient(colors: [c.opacity(0.6), c], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(max(1, 360 * frac))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: c.opacity(0.55), radius: lineWidth * 0.5, y: lineWidth * 0.25)
            // połysk na łuku (efekt tuby)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth * 0.28, lineCap: .round))
                .frame(width: size - lineWidth * 0.45, height: size - lineWidth * 0.45)
                .rotationEffect(.degrees(-90))
                .blur(radius: 0.5)
            VStack(spacing: 0) {
                CountingPercent(value: shown, font: .system(size: size * 0.26, weight: .bold, design: .rounded))
                if let label {
                    Text(label).font(.system(size: size * 0.1)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(duration: 1.3, bounce: 0.12).delay(0.2)) { shown = percent }
        }
        .onChange(of: percent) { _, v in
            withAnimation(.smooth(duration: 0.8)) { shown = v }
        }
    }
}

/// Mały znacznik statusu.
struct Pill: View {
    let text: String
    let color: Color
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11.5, weight: .semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @State private var flipped = false

    var body: some View {
        HStack(spacing: 14) {
            GlossyIcon(symbol: icon, tint: tint, size: 44, radius: 12)
                .rotation3DEffect(.degrees(flipped ? 0 : -110), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.05)) { flipped = true } }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
