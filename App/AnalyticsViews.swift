import Charts
import SwiftUI

private let pl = Locale(identifier: "pl_PL")

// MARK: - Klocki

/// Jedna komórka z metryką: tytuł, wartość, dopisek.
struct StatCell: View {
    let title: String
    let value: String
    var sub: String? = nil
    var tint: Color = .primary
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let info = help ?? Explain.metric[title] {
                    InfoButton(text: info, size: 11)
                }
            }
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let sub {
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.045)))
    }
}

/// Siatka metryk w kilku kolumnach.
struct MetricGrid<Content: View>: View {
    var columns: Int = 4
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns),
                  alignment: .leading, spacing: 10) {
            content
        }
    }
}

/// Lista pozioma z paskami: nazwa, pasek udziału, wartość.
struct RankedBars: View {
    struct Item: Identifiable {
        var name: String
        var fraction: Double
        var value: String
        var detail: String? = nil
        var color: Color
        var id: String { name }
    }
    let items: [Item]
    var nameWidth: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
                        .frame(width: 16, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if let d = it.detail {
                            Text(d).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(width: nameWidth, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(it.color.opacity(0.13))
                            Capsule().fill(it.color.gradient)
                                .frame(width: max(5, g.size.width * min(1, it.fraction)))
                        }
                    }
                    .frame(height: 9)
                    Text(it.value).font(.system(size: 12.5, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(width: 92, alignment: .trailing)
                }
            }
        }
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private func toneColor(_ tone: String) -> Color {
    switch tone {
    case "good": Palette.mint
    case "warn": Palette.amber
    case "bad": Palette.coral
    default: Palette.blue
    }
}

// MARK: - Przegląd

struct InsightsCard: View {
    let insights: [Insight]

    var body: some View {
        Card(title: "Wnioski", subtitle: "automatyczna analiza ostatnich 30 dni", icon: "lightbulb.fill", tint: Palette.amber) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 10) {
                ForEach(insights) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(toneColor(tip.tone))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(toneColor(tip.tone).opacity(0.15)))
                        Text(tip.text).font(.system(size: 12.5))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ThirtyDaysCard: View {
    let a: Analytics

    var body: some View {
        let t = a.d30
        Card(title: "30 dni w liczbach", subtitle: "Claude Code na tym Macu · % limitu tygodniowego przeliczone z lokalnych logów",
             icon: "number.square.fill", tint: Palette.indigo) {
            if let t {
                MetricGrid(columns: 4) {
                    StatCell(title: "Tokeny łącznie", value: Fmt.tokens(t.allTokens),
                             sub: "\(Fmt.tokens(t.out)) wygenerowanych")
                    StatCell(title: "Zużycie limitu tygodnia", value: a.limit(t.cost),
                             sub: a.limitPct(t.cost).map { "≈ \(String(format: "%.1f", $0 / 100).replacingOccurrences(of: ".", with: ",")) tyg. limitu · \(a.limit(t.cost / 30)) dziennie" } ?? "brak kalibracji",
                             tint: Palette.claude)
                    StatCell(title: "Odpowiedzi modelu", value: "\(t.responses)",
                             sub: "\(t.tools) wywołań narzędzi")
                    StatCell(title: "Sesje", value: "\(t.sessions ?? 0)",
                             sub: "\(t.projects ?? 0) projektów · \(Int(a.sessions.totalActiveHours.rounded())) h pracy")
                    StatCell(title: "Trafienia cache", value: Fmt.share(a.cache.hitRate),
                             sub: t.cost > 0 ? "bez cache zużycie ok. \(Int(((t.cost + a.cache.savedUSD) / t.cost).rounded()))× większe" : "",
                             tint: Palette.mint)
                    StatCell(title: "Kontekst na odpowiedź", value: Fmt.tokens(a.cache.contextPerResponse),
                             sub: "średnio tokenów wejścia")
                    StatCell(title: "Myślenie", value: Fmt.share(Double(t.think) / Double(max(1, t.out))),
                             sub: "tokenów wyjścia to rozumowanie")
                    if let p = a.limitPct(t.cost), p > 0 {
                        StatCell(title: "1% limitu tygodnia", value: "≈ \(Int((Double(t.responses) / p).rounded())) odp.",
                                 sub: "≈ \(Fmt.tokens(Int(Double(t.out) / p))) wygenerowanych tokenów", tint: Palette.violet)
                    } else {
                        StatCell(title: "1% limitu tygodnia", value: "—", sub: "za mało danych")
                    }
                }
            }
        }
    }
}

// MARK: - Tydzień

struct PaceCard: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let s = model.usage?.stats
        let w = model.usage?.weekly
        let used = w?.percent ?? 0
        let daysLeft = max(0.01, (w?.resetDate?.timeIntervalSince(model.now) ?? 0) / 86400)
        let need = max(0, 100 - used) / daysLeft
        let rate = s?.burn?.h6 ?? s?.burn?.h24 ?? s?.weekAvgPerDay
        let runway = rate.flatMap { $0 > 0.05 ? max(0, 100 - used) / $0 : nil }
        Card(title: "Tempo zużycia", subtitle: "% limitu tygodniowego na dobę · z odczytów serwera",
             icon: "speedometer", tint: Palette.teal) {
            MetricGrid(columns: 4) {
                StatCell(title: "Ostatnia godzina", value: s?.burn?.h1.map { Fmt.pct1($0) } ?? "—",
                         sub: "w przeliczeniu na dobę", tint: Fmt.color((s?.burn?.h1 ?? 0) * 7))
                StatCell(title: "Ostatnie 6 h", value: s?.burn?.h6.map { Fmt.pct1($0) } ?? "—",
                         sub: "w przeliczeniu na dobę", tint: Fmt.color((s?.burn?.h6 ?? 0) * 7))
                StatCell(title: "Ostatnie 24 h", value: s?.burn?.h24.map { Fmt.pct1($0) } ?? "—",
                         sub: s?.burn?.h24 == nil ? "historia krótsza niż doba" : "rzeczywisty przyrost")
                StatCell(title: "Średnio w tym tygodniu", value: s?.weekAvgPerDay.map { Fmt.pct1($0) } ?? "—",
                         sub: "od resetu")
                StatCell(title: "Bezpieczne tempo", value: Fmt.pct1(need),
                         sub: "na dobę do resetu, by zużyć ≤ 100%", tint: Palette.mint)
                StatCell(title: "Zapas przy obecnym tempie",
                         value: runway.map { $0 > 14 ? "> 2 tyg." : String(format: "%.1f dnia", $0).replacingOccurrences(of: ".", with: ",") } ?? "—",
                         sub: runway.map { $0 < daysLeft ? "gdyby tempo z 6 h trwało bez przerwy" : "wystarczy do resetu" } ?? "",
                         tint: runway.map { $0 < daysLeft ? Palette.amber : Palette.mint } ?? .primary)
                StatCell(title: "Do resetu", value: Fmt.countdown(w?.resetDate, now: model.now),
                         sub: Fmt.resetAt(w?.resetDate, now: model.now))
                StatCell(title: "Prosta proporcja", value: s?.linearWeekly.map { "~\(Int($0.rounded()))%" } ?? "—",
                         sub: "dla porównania z prognozą")
            }
        }
    }
}

struct WeeksCompareCard: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let weeks = (model.usage?.stats?.weeks ?? []).reversed()
        let current = model.usage?.weekly?.percent ?? 0
        let proj = model.usage?.stats?.projectedWeekly
        Card(title: "Porównanie tygodni", subtitle: "suma zużycia w poprzednich okresach limitu · szac. = z lokalnych logów",
             icon: "chart.bar.doc.horizontal", tint: Palette.blue) {
            if weeks.isEmpty {
                EmptyNote(text: "Porównanie pojawi się, gdy zbierze się historia z poprzednich tygodni.")
            } else {
                Chart {
                    ForEach(Array(weeks)) { wk in
                        let label = "\(shortDay(wk.start))–\(shortDay(wk.end, minusDay: true))"
                        BarMark(x: .value("Tydzień", label), y: .value("%", min(wk.pct, 100)), width: .ratio(0.55))
                            .foregroundStyle(Palette.gradient(Palette.slate.opacity(wk.estimated ? 0.5 : 0.9), Palette.blue.opacity(wk.estimated ? 0.5 : 0.9)))
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text((wk.pct >= 100 ? "100%+" : "\(Int(wk.pct.rounded()))%") + (wk.estimated ? " szac." : ""))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                    }
                    BarMark(x: .value("Tydzień", "ten tydzień"), y: .value("%", current), width: .ratio(0.55))
                        .foregroundStyle(Palette.claudeGradient)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(Int(current.rounded()))%" + (proj.map { " → ~\(Int($0.rounded()))%" } ?? ""))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.claude)
                        }
                    RuleMark(y: .value("Limit", 100))
                        .foregroundStyle(Palette.coral.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...115)
                .chartYAxis(.hidden)
                .frame(height: 190)
            }
        }
    }

    private func shortDay(_ iso: String, minusDay: Bool = false) -> String {
        guard var d = DateFormatter.isoDay.date(from: iso) else { return iso }
        if minusDay { d = d.addingTimeInterval(-86400) }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(pl))
    }
}

struct WeekdayProfileCard: View {
    let factors: [Double]

    var body: some View {
        let names = ["pon.", "wt.", "śr.", "czw.", "pt.", "sob.", "niedz."]
        Card(title: "Profil dni tygodnia", subtitle: "intensywność względem przeciętnego dnia (1,0×) · używane w prognozie",
             icon: "waveform.path", tint: Palette.violet) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<min(7, factors.count), id: \.self) { i in
                    let f = factors[i]
                    VStack(spacing: 5) {
                        Text(String(format: "%.1f×", f).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(f >= 1 ? Palette.gradient(Palette.claude, Palette.coral) : Palette.gradient(Palette.teal, Palette.blue))
                            .frame(height: max(6, 90 * min(f, 2.2) / 2.2))
                        Text(names[i]).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 135, alignment: .bottom)
        }
    }
}

// MARK: - Okna 5h

struct FiveHourAdvancedCard: View {
    @ObservedObject var model: ReportModel
    let a: Analytics

    var body: some View {
        let wins = a.fiveHourWindows.filter { $0.estPct != nil }
        let est = wins.compactMap(\.estPct)
        let over80 = est.filter { $0 >= 80 }.count
        let avgActive = a.fiveHourWindows.isEmpty ? 0 : Double(a.fiveHourWindows.map(\.activeMin).reduce(0, +)) / Double(a.fiveHourWindows.count)
        let f5 = model.usage?.stats?.fiveHourForecast
        Card(title: "Analiza okien 5h", subtitle: "odtworzone z lokalnych logów i skalibrowane do bieżącego okna serwera",
             icon: "square.stack.3d.down.right.fill", tint: Palette.indigo) {
            MetricGrid(columns: 4) {
                StatCell(title: "Okna w 30 dni", value: "\(a.fiveHourWindows.count)",
                         sub: "aktywnych okien z pracą w Claude Code")
                StatCell(title: "Średni szczyt (szac.)", value: est.isEmpty ? "—" : "\(Int((est.reduce(0, +) / Double(est.count)).rounded()))%",
                         sub: "na okno")
                StatCell(title: "Okna ≥ 80% (szac.)", value: "\(over80)",
                         sub: est.isEmpty ? "" : "\(Int((Double(over80) / Double(est.count) * 100).rounded()))% okien",
                         tint: over80 > 0 ? Palette.amber : .primary)
                StatCell(title: "Aktywny czas w oknie", value: Fmt.minutes(avgActive), sub: "średnio od startu do ostatniej odpowiedzi")
                StatCell(title: "Tempo teraz", value: f5.map { "\(Fmt.pct1($0.ratePerHour))/h" } ?? "—",
                         sub: "z ostatniej godziny")
                StatCell(title: "Do wyczerpania", value: timeToLimit(f5), sub: "przy obecnym tempie",
                         tint: f5?.hitDate != nil ? Palette.coral : Palette.mint)
                let full = a.fiveHourFactor.flatMap { a.limitPct(100 / $0) }
                StatCell(title: "Pełne okno 5h", value: full.map { "\(Fmt.limit($0)) limitu" } ?? "—",
                         sub: "tyle limitu tygodniowego zużywa okno 5h w 100%")
                StatCell(title: "Pełnych okien na tydzień", value: full.map { $0 > 0 ? String(format: "%.1f", 100 / $0).replacingOccurrences(of: ".", with: ",") : "—" } ?? "—",
                         sub: "ile maksymalnych okien mieści limit tygodniowy")
            }
            if !wins.isEmpty {
                Text("Szacowany szczyt kolejnych okien").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.top, 6)
                Chart {
                    ForEach(wins) { w in
                        if let d = w.startDate, let p = w.estPct {
                            BarMark(x: .value("Start", d, unit: .hour), y: .value("%", p), width: .fixed(7))
                                .foregroundStyle(Fmt.color(p).gradient)
                                .cornerRadius(3)
                        }
                    }
                    RuleMark(y: .value("Limit", 100))
                        .foregroundStyle(Palette.coral.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...110)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))%") }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(pl))
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private func timeToLimit(_ f: FiveHourForecast?) -> String {
        guard let f else { return "—" }
        if let hit = f.hitDate {
            return Fmt.minutes(max(0, hit.timeIntervalSince(model.now) / 60))
        }
        return "nie grozi"
    }
}

struct WindowStartsCard: View {
    let starts: [Int]

    var body: some View {
        let maxV = max(1, starts.max() ?? 1)
        Card(title: "Kiedy zaczynasz okna", subtitle: "godzina startu okien 5h w ostatnich 30 dniach",
             icon: "clock.badge.checkmark.fill", tint: Palette.violet) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    let v = h < starts.count ? starts[h] : 0
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(v > 0 ? AnyShapeStyle(Palette.gradient(Palette.violet, Palette.indigo)) : AnyShapeStyle(.primary.opacity(0.07)))
                            .frame(height: max(4, 80 * Double(v) / Double(maxV)))
                            .help("\(h):00 — \(v) okien")
                        Text(h % 3 == 0 ? "\(h)" : " ").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 105, alignment: .bottom)
        }
    }
}

// MARK: - Historia

/// Mapa ciepła: dzień tygodnia × godzina.
struct HeatmapCard: View {
    let matrix: [[Double]]
    let responses: [[Int]]
    var k: Double? = nil
    @State private var hover: (Int, Int)? = nil
    @State private var canvasWidth: CGFloat = 1

    private func hoverAt(_ p: CGPoint) {
        let gap: CGFloat = 3
        let cw = (canvasWidth - gap * 23) / 24
        let h = Int(p.x / (cw + gap)), wd = Int(p.y / (22 + gap))
        guard (0..<24).contains(h), (0..<7).contains(wd) else { hover = nil; return }
        if hover.map({ $0 != (wd, h) }) ?? true { hover = (wd, h) }
    }

    var body: some View {
        let names = ["pon.", "wt.", "śr.", "czw.", "pt.", "sob.", "niedz."]
        let maxV = max(0.0001, matrix.flatMap { $0 }.max() ?? 0.0001)
        let total = max(0.0001, matrix.flatMap { $0 }.reduce(0, +))
        Card(title: "Mapa aktywności", subtitle: "zużycie wg dnia tygodnia i godziny · 30 dni · najedź, by zobaczyć szczegóły",
             icon: "square.grid.3x3.fill", tint: Palette.claude) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 3) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<7, id: \.self) { wd in
                            Text(names[wd]).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: 44, height: 22, alignment: .leading)
                        }
                    }
                    // jedno płótno zamiast 168 osobnych widoków
                    Canvas { ctx, size in
                        let gap: CGFloat = 3
                        let cw = (size.width - gap * 23) / 24, ch: CGFloat = 22
                        for wd in 0..<7 {
                            for h in 0..<24 {
                                let v = wd < matrix.count && h < matrix[wd].count ? matrix[wd][h] : 0
                                let rect = CGRect(x: CGFloat(h) * (cw + gap), y: CGFloat(wd) * (ch + gap), width: cw, height: ch)
                                let path = Path(roundedRect: rect, cornerRadius: 4, style: .continuous)
                                let color = v > 0 ? Palette.claude.opacity(0.12 + 0.88 * pow(v / maxV, 0.6)) : Color.primary.opacity(0.05)
                                ctx.fill(path, with: .color(color))
                                if let hv = hover, hv == (wd, h) {
                                    ctx.stroke(path.strokedPath(.init(lineWidth: 1.5)), with: .color(.white.opacity(0.9)))
                                }
                            }
                        }
                    }
                    .frame(height: 7 * 22 + 6 * 3)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            hoverAt(p)
                        case .ended:
                            hover = nil
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
                }
                HStack(spacing: 3) {
                    Text("").frame(width: 44)
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 3 == 0 ? "\(h)" : "").font(.system(size: 9.5)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    if let (wd, h) = hover {
                        let v = matrix[wd][h]
                        let n = wd < responses.count && h < responses[wd].count ? responses[wd][h] : 0
                        Text("\(names[wd]) \(h):00–\(h + 1):00 · \(n) odpowiedzi · \(limitText(v)) limitu tyg. · \(Fmt.share(v / total)) całości")
                            .font(.system(size: 12, weight: .medium))
                            .transition(.opacity)
                    } else {
                        Text("mniej").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        ForEach(0..<5) { i in
                            RoundedRectangle(cornerRadius: 3).fill(Palette.claude.opacity(0.12 + 0.22 * Double(i))).frame(width: 14, height: 10)
                        }
                        Text("więcej").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 18)
                .padding(.top, 6)
            }
        }
    }
}

extension HeatmapCard {
    func limitText(_ units: Double) -> String { k.map { Fmt.limit(units * $0) } ?? "—" }
}

struct HistoryStatsCard: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let vals = model.completeDays.map(\.pct)
        let sorted = vals.sorted()
        let q = { (p: Double) -> Double? in
            guard !sorted.isEmpty else { return nil }
            let i = p * Double(sorted.count - 1)
            let lo = Int(i), hi = min(lo + 1, sorted.count - 1)
            return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - Double(lo))
        }
        let streak = longestStreak(model.completeDays.map { $0.pct > 0.5 })
        let trend = slope(Array(vals.suffix(14)))
        let cal = Calendar(identifier: .iso8601)
        let weekend = model.completeDays.filter { [1, 7].contains(cal.component(.weekday, from: $0.date)) }.map(\.pct).reduce(0, +)
        let all = max(0.0001, vals.reduce(0, +))
        let std: Double = {
            guard vals.count > 1 else { return 0 }
            let m = all / Double(vals.count)
            return (vals.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(vals.count - 1)).squareRoot()
        }()
        Card(title: "Statystyki rozkładu", subtitle: "dzienne zużycie jako % limitu tygodniowego · pełne dni",
             icon: "function", tint: Palette.teal) {
            MetricGrid(columns: 4) {
                StatCell(title: "Mediana dnia", value: q(0.5).map(Fmt.pct1) ?? "—", sub: "połowa dni poniżej")
                StatCell(title: "90. percentyl", value: q(0.9).map(Fmt.pct1) ?? "—", sub: "intensywny dzień", tint: Palette.amber)
                StatCell(title: "Odchylenie std.", value: Fmt.pct1(std), sub: "zmienność dzień do dnia")
                StatCell(title: "Trend 14 dni", value: trend.map { (t: Double) in (t >= 0 ? "+" : "") + Fmt.pct1(t) } ?? "—",
                         sub: "zmiana dziennego zużycia na dzień",
                         tint: (trend ?? 0) > 0.3 ? Palette.coral : (trend ?? 0) < -0.3 ? Palette.mint : .primary)
                StatCell(title: "Najdłuższa seria", value: "\(streak) dni", sub: "aktywnych dni z rzędu")
                StatCell(title: "Weekendy", value: Fmt.share(weekend / all), sub: "zużycia przypada na sob.–niedz.")
                StatCell(title: "Dni powyżej tempa", value: "\(model.daysAbovePace)", sub: "> 14,3% limitu w ciągu dnia")
                StatCell(title: "Dni aktywne", value: "\(model.activeDays) / \(vals.count)", sub: "z pracą z Claude")
            }
        }
    }

    private func longestStreak(_ flags: [Bool]) -> Int {
        var best = 0, cur = 0
        for f in flags { cur = f ? cur + 1 : 0; best = max(best, cur) }
        return best
    }

    /// Nachylenie prostej regresji (zmiana na dzień).
    private func slope(_ ys: [Double]) -> Double? {
        guard ys.count >= 5 else { return nil }
        let n = Double(ys.count)
        let xs = (0..<ys.count).map(Double.init)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        return den > 0 ? num / den : nil
    }
}

struct DailyValueCard: View {
    let daily: [DailyCounters]
    let k: Double

    var body: some View {
        let firstActive = daily.firstIndex { $0.responses > 0 } ?? 0
        let pts = daily.dropFirst(firstActive).compactMap { d in d.day.map { (date: $0, d: d) } }
        let avg: [(Date, Double)] = pts.indices.map { i in
            let w = pts[max(0, i - 6)...i]
            return (pts[i].date, w.map(\.d.cost).reduce(0, +) / Double(w.count))
        }
        Card(title: "Zużycie wg modelu dzień po dniu", subtitle: "% limitu tygodniowego z lokalnych logów · linia = średnia krocząca 7 dni · kolor = model",
             icon: "dollarsign.arrow.circlepath", tint: Palette.mint) {
            Chart {
                ForEach(pts, id: \.d.date) { p in
                    ForEach(p.d.models.sorted(by: { $0.key < $1.key }), id: \.key) { fam, cost in
                        BarMark(x: .value("Dzień", p.date, unit: .day), y: .value("%", cost * k))
                            .foregroundStyle(by: .value("Model", fam))
                            .cornerRadius(3)
                    }
                }
                ForEach(avg, id: \.0) { d, v in
                    LineMark(x: .value("Dzień", d, unit: .day), y: .value("Średnia", v * k), series: .value("s", "avg"))
                        .foregroundStyle(Palette.slate)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale(range: [Palette.claude, Palette.blue, Palette.violet, Palette.teal, Palette.amber])
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))%") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, pts.count / 7))) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(pl))
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
        }
    }
}

// MARK: - Źródła i modele

struct ModelsCard: View {
    let a: Analytics

    var body: some View {
        Card(title: "Modele", subtitle: "Claude Code · 30 dni", icon: "cpu.fill", tint: Palette.indigo) {
            VStack(spacing: 0) {
                row(["Model", "Odpowiedzi", "Wygenerowane", "Śr. odpowiedź", "Cache", "Limit tyg.", "Udział"], header: true)
                Divider().opacity(0.5)
                ForEach(a.models) { m in
                    row([m.model, "\(m.responses)", Fmt.tokens(m.out), "\(m.avgOut) tok.", Fmt.share(m.cacheHit),
                         a.limit(m.cost), Fmt.share(m.share)])
                    Divider().opacity(0.25)
                }
            }
        }
    }

    private func row(_ cols: [String], header: Bool = false) -> some View {
        HStack {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(.system(size: header ? 11.5 : 13, weight: header ? .semibold : (i == 0 ? .medium : .regular),
                                  design: i == 0 ? .monospaced : .rounded))
                    .foregroundStyle(header ? .secondary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: i == 0 ? .infinity : 96, alignment: i == 0 ? .leading : .trailing)
                    .frame(width: i == 0 ? nil : 96)
            }
        }
        .padding(.vertical, 7)
    }
}

struct TokenBreakdownCard: View {
    let c: Counters

    var body: some View {
        let parts: [(String, Int, Color, String)] = [
            ("Odczyt z cache", c.cr, Palette.mint, "kontekst ponownie użyty — najtańszy"),
            ("Zapis do cache", c.cw, Palette.amber, "nowy kontekst zapisany na później"),
            ("Świeże wejście", c.inp, Palette.blue, "tokeny wejścia bez cache"),
            ("Wygenerowane", c.out, Palette.claude, "odpowiedzi modelu"),
            ("w tym myślenie", c.think, Palette.violet, "rozumowanie przed odpowiedzią"),
        ]
        let total = Double(max(1, c.allTokens))
        Card(title: "Struktura tokenów", subtitle: "\(Fmt.tokens(c.allTokens)) tokenów w 30 dni · skala logarytmiczna pasków",
             icon: "square.stack.3d.up.fill", tint: Palette.teal) {
            RankedBars(items: parts.map { name, v, col, d in
                RankedBars.Item(name: name, fraction: log10(Double(max(1, v))) / log10(total),
                                value: Fmt.tokens(v), detail: "\(d) · \(String(format: "%.2f", Double(v) / total * 100).replacingOccurrences(of: ".", with: ","))%",
                                color: col)
            }, nameWidth: 290)
        }
    }
}

struct GroupsCard: View {
    let a: Analytics

    var body: some View {
        Card(title: "Sposób pracy", subtitle: "udział w zużyciu · % limitu tygodniowego w 30 dni", icon: "slider.horizontal.3", tint: Palette.slate) {
            HStack(alignment: .top, spacing: 24) {
                group("Aplikacja", a.entrypoints, Palette.blue)
                group("Poziom wysiłku", a.efforts, Palette.violet)
                group("Kto pracował", a.sidechain, Palette.teal)
            }
        }
    }

    private func group(_ title: String, _ items: [GroupUse], _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items) { g in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(g.name).font(.system(size: 12.5)).lineLimit(1)
                        Spacer()
                        Text(Fmt.share(g.share)).font(.system(size: 12.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.opacity(0.13))
                            Capsule().fill(c.gradient).frame(width: max(4, geo.size.width * g.share))
                        }
                    }
                    .frame(height: 6)
                    Text("\(g.responses) odpowiedzi · \(a.limit(g.cost)) limitu tyg.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Projekty i sesje

struct ProjectsCard: View {
    let a: Analytics

    var body: some View {
        let maxCost = max(0.01, a.projects.first?.cost ?? 1)
        Card(title: "Projekty", subtitle: "\(a.projectCount) projektów w 30 dni · zużycie jako % limitu tygodniowego",
             icon: "folder.fill", tint: Palette.amber) {
            RankedBars(items: a.projects.prefix(12).enumerated().map { i, p in
                RankedBars.Item(name: p.name, fraction: p.cost / maxCost,
                                value: "\(a.limit(p.cost)) limitu",
                                detail: "\(p.sessions) sesji · \(p.responses) odp. · \(p.lastDate.map { "ostatnio " + $0.formatted(.relative(presentation: .named).locale(pl)) } ?? "")",
                                color: [Palette.claude, Palette.amber, Palette.teal, Palette.blue, Palette.violet, Palette.pink][i % 6])
            }, nameWidth: 230)
        }
    }
}

struct SessionsCard: View {
    let a: Analytics

    var body: some View {
        let s = a.sessions
        Card(title: "Sesje", subtitle: "aktywny czas = suma odcinków bez przerwy dłuższej niż 15 min",
             icon: "bubble.left.and.text.bubble.right.fill", tint: Palette.blue) {
            MetricGrid(columns: 5) {
                StatCell(title: "Liczba sesji", value: "\(s.count)")
                StatCell(title: "Typowa sesja", value: Fmt.minutes(s.medianActiveMin), sub: "mediana")
                StatCell(title: "Długa sesja", value: Fmt.minutes(s.p90ActiveMin), sub: "90. percentyl")
                StatCell(title: "Odpowiedzi / sesję", value: "\(Int(s.medianResponses.rounded()))", sub: "mediana")
                StatCell(title: "Czas pracy", value: "\(Int(s.totalActiveHours.rounded())) h", sub: "łącznie")
            }
            Text("Najbardziej wymagające sesje").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(s.top) { x in
                    HStack(spacing: 12) {
                        Image(systemName: "text.bubble.fill").foregroundStyle(Palette.blue.gradient)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(x.project).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(x.startDate.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(pl)) } ?? "")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Pill(text: Fmt.minutes(Double(x.activeMin)), color: Palette.teal, icon: "timer")
                        Text("\(x.responses) odp.").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                        Text(a.limit(x.cost)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    Divider().opacity(0.25)
                }
            }
        }
    }
}

struct ToolsCard: View {
    let a: Analytics

    var body: some View {
        let maxC = Double(max(1, a.tools.first?.count ?? 1))
        let responses = a.d30?.responses ?? 1
        Card(title: "Narzędzia", subtitle: "\(a.toolTotal) wywołań · \(String(format: "%.1f", Double(a.toolTotal) / Double(max(1, responses))).replacingOccurrences(of: ".", with: ",")) na odpowiedź",
             icon: "wrench.and.screwdriver.fill", tint: Palette.teal) {
            RankedBars(items: a.tools.prefix(12).map { t in
                RankedBars.Item(name: t.name, fraction: Double(t.count) / maxC,
                                value: "\(t.count)", detail: Fmt.share(Double(t.count) / Double(max(1, a.toolTotal))) + " wywołań",
                                color: t.name.hasPrefix("MCP") ? Palette.violet : Palette.teal)
            }, nameWidth: 200)
            let stops = a.stopReasons.sorted { $0.value > $1.value }
            HStack(spacing: 8) {
                Text("Zakończenia odpowiedzi:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                ForEach(stops, id: \.key) { k, v in
                    Pill(text: "\(stopName(k)) \(v)", color: k == "max_tokens" ? Palette.coral : Palette.slate)
                }
            }
            .padding(.top, 4)
        }
    }

    private func stopName(_ k: String) -> String {
        switch k {
        case "tool_use": "narzędzie"
        case "end_turn": "koniec"
        case "max_tokens": "ucięte"
        case "stop_sequence": "sekwencja"
        case "refusal": "odmowa"
        case "?": "inne"
        default: k
        }
    }
}
