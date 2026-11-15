import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: Usage?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, usage: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let u = UsageStore.load()
        completion(UsageEntry(date: .now, usage: context.isPreview ? (u ?? .placeholder) : u))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // Prośba o odświeżenie co minutę (macOS może to rozrzedzić, żeby oszczędzać baterię).
        let entry = UsageEntry(date: .now, usage: UsageStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }
}

private let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

struct Ring: View {
    let window: LimitWindow
    let title: String
    let now: Date
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(window.percent, 100) / 100)
                    .stroke(Fmt.color(window.percent), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(window.shown)
                    .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 56, height: 56)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(Fmt.countdown(window.resetDate, now: now))
                .font(.system(size: 12).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(Fmt.resetAt(window.resetDate, now: now))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BarRow: View {
    let window: LimitWindow
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(window.shown)
                    .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Fmt.color(window.percent))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Fmt.color(window.percent))
                        .frame(width: max(4, g.size.width * min(window.percent, 100) / 100))
                }
            }
            .frame(height: 7)
            Text(Fmt.resetIn(window.resetDate, now: now))
                .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

struct Header: View {
    let usage: Usage
    var showTime = true
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(accent)
            Text("Claude").font(.system(size: 13, weight: .semibold)).fixedSize()
            if !Fmt.planName(usage.plan).isEmpty {
                Text(Fmt.planName(usage.plan)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
            }
            Spacer(minLength: 2)
            if usage.isProblem {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            } else if showTime, let d = usage.dataDate {
                Text(d, style: .time).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct Notice: View {
    let usage: Usage
    var body: some View {
        if usage.isProblem, let msg = usage.message {
            Text(msg).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).minimumScaleFactor(0.8)
        }
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    var body: some View {
        if let u = entry.usage, !u.windows.isEmpty {
            switch family {
            case .systemSmall: small(u)
            case .systemLarge: large(u)
            default: medium(u)
            }
        } else {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "sparkle").foregroundStyle(accent)
                    Text("Claude").font(.caption.weight(.semibold))
                    Spacer()
                }
                Spacer()
                Text("Brak danych").font(.headline)
                Text(entry.usage?.message ?? "Uruchom install.sh, żeby pobierać limity.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
        }
    }

    func small(_ u: Usage) -> some View {
        VStack(spacing: 4) {
            Header(usage: u, showTime: false)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let w = u.fiveHour { Ring(window: w, title: "5h", now: entry.date) }
                if let w = u.weekly { Ring(window: w, title: "Tydzień", now: entry.date) }
            }
            Spacer(minLength: 0)
            Notice(usage: u)
        }
    }

    func medium(_ u: Usage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(usage: u)
            Spacer(minLength: 0)
            if let w = u.fiveHour { BarRow(window: w, now: entry.date) }
            if let w = u.weekly { BarRow(window: w, now: entry.date) }
            Spacer(minLength: 0)
            Notice(usage: u)
        }
    }

    func large(_ u: Usage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Header(usage: u)
            if let w = u.fiveHour { BarRow(window: w, now: entry.date) }
            if let w = u.weekly { BarRow(window: w, now: entry.date) }
            if let s = u.stats {
                Divider()
                StatsTiles(stats: s)
                if let days = s.daily, days.contains(where: { $0.pct != nil }) {
                    DailyChart(days: days)
                }
                Sources(sources: s.sources ?? [])
            }
            Spacer(minLength: 0)
            Notice(usage: u)
        }
    }
}

struct Tile: View {
    let title: String
    let value: String
    let sub: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsTiles: View {
    let stats: Stats
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let p = stats.projectedWeekly {
                Tile(title: "Prognoza tyg.", value: "~\(Int(p.rounded()))%",
                     sub: stats.forecast.map { "zakres \(Fmt.range($0.low, $0.high))" }
                        ?? (p >= 100 ? "zabraknie limitu" : "przy tym tempie"),
                     color: Fmt.color(p))
            } else {
                Tile(title: "Prognoza tyg.", value: "—", sub: "za wcześnie")
            }
            if let a = stats.avgDaily30 {
                Tile(title: "Średnio / dzień", value: Fmt.pct1(a),
                     sub: "z \(stats.daysCounted ?? 0) dni")
            } else {
                Tile(title: "Średnio / dzień", value: "—", sub: "brak danych")
            }
            if let f = stats.fiveHour, let avg = f.avgPeak {
                Tile(title: "Okna 5h", value: "śr. \(Int(avg.rounded()))%",
                     sub: f.limitHits > 0 ? "limit: \(f.limitHits)×" : "\(f.windows) okien, bez limitu",
                     color: Fmt.color(avg))
            } else {
                Tile(title: "Okna 5h", value: "—", sub: "zbieram dane")
            }
        }
    }
}

struct DailyChart: View {
    let days: [DailyUse]
    var body: some View {
        let maxV = max(days.compactMap(\.pct).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Dziennie, % limitu tygodnia").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if days.contains(where: { $0.estimated && $0.pct != nil }) {
                    Text("jasne = szacunek").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days) { d in
                    let v = d.pct ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d.pct == nil ? AnyShapeStyle(.quaternary)
                              : AnyShapeStyle(Fmt.color(v * 7).opacity(d.estimated ? 0.45 : 1)))
                        .frame(height: d.pct == nil ? 2 : max(3, CGFloat(v / maxV) * 46))
                }
            }
            .frame(height: 46, alignment: .bottom)
            HStack {
                Text(Self.label(days.first?.date)).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Text("dziś").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    static func label(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(Int(p[2]) ?? 0).\(p[1])" : iso
    }
}

struct Sources: View {
    let sources: [SourceShare]
    var body: some View {
        let shown = sources.filter { $0.percent > 0 }
        if !shown.isEmpty {
            HStack(spacing: 4) {
                Text("Tydzień wg źródła:").foregroundStyle(.secondary)
                Text(shown.map { "\($0.name) \(Int($0.percent))%" }.joined(separator: " · "))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 11))
        }
    }
}

@main
struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            WidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "claudeusage://raport"))
        }
        .configurationDisplayName("Limity Claude")
        .description("Procent wykorzystania limitu 5h i tygodniowego.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
