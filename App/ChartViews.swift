import Charts
import SwiftUI

private let pl = Locale(identifier: "pl_PL")

private func percentAxis(_ values: [Double]) -> some AxisContent {
    AxisMarks(position: .trailing, values: values) { v in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
        AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))%") }
    }
}

/// Bieżące okno 5h.
struct FiveHourNowChart: View {
    @ObservedObject var model: ReportModel
    var height: CGFloat = 220

    var body: some View {
        let pts = model.fiveHourSeries.filter { $0.h != nil }
        let reset = model.usage?.fiveHour?.resetDate ?? model.now
        let start = reset.addingTimeInterval(-5 * 3600)
        let c = Fmt.color(model.usage?.fiveHour?.percent ?? 0)
        Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("Czas", p.t), y: .value("%", p.h ?? 0))
                    .foregroundStyle(LinearGradient(colors: [c.opacity(0.35), c.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Czas", p.t), y: .value("%", p.h ?? 0))
                    .foregroundStyle(c)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.stepEnd)
            }
            RuleMark(y: .value("Limit", 100))
                .foregroundStyle(Palette.coral.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            RuleMark(x: .value("Teraz", model.now))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: start...reset)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let d = value.as(Date.self) { Text("\(Calendar.current.component(.hour, from: d)):00") }
                }
            }
        }
        .chartYAxis { percentAxis([0, 50, 100]) }
        .overlay {
            if pts.isEmpty {
                Text("Zapis tego okna dopiero się zaczyna").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
    }
}

/// Dzienne zużycie z 30 dni.
struct Daily30Chart: View {
    @ObservedObject var model: ReportModel
    var height: CGFloat = 230

    var body: some View {
        let days = model.days30
        let avg = model.usage?.stats?.avgDaily30
        Chart {
            ForEach(days) { d in
                BarMark(x: .value("Dzień", d.date, unit: .day), y: .value("%", d.pct))
                    .foregroundStyle(Palette.gradient(Fmt.color(d.pct * 7).opacity(0.75), Fmt.color(d.pct * 7)))
                    .opacity(d.estimated ? 0.5 : 1)
                    .cornerRadius(4)
            }
            if let avg {
                RuleMark(y: .value("Średnia", avg))
                    .foregroundStyle(Palette.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Pill(text: "średnio " + Fmt.pct1(avg), color: Palette.blue)
                    }
            }
            RuleMark(y: .value("Tempo limitu", ReportModel.pacePerDay))
                .foregroundStyle(Palette.coral.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .bottom, alignment: .trailing) {
                    Text("14,3%/dzień = cały limit w tydzień").font(.caption2).foregroundStyle(Palette.coral)
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(pl))
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) { v in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") }
        } }
        .frame(height: height)
    }
}

/// Dni bieżącego tygodnia limitów.
struct ThisWeekDaysChart: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let days = model.thisWeekDays
        let maxV = max(days.compactMap(\.pct).max() ?? 1, ReportModel.pacePerDay)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                let isToday = Calendar.current.isDate(d.date, inSameDayAs: model.now)
                VStack(spacing: 6) {
                    Text(d.pct.map(Fmt.pct1) ?? "—")
                        .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(d.pct == nil ? .tertiary : .primary)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6))
                        if let v = d.pct {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Palette.gradient(Fmt.color(v * 7).opacity(0.7), Fmt.color(v * 7)))
                                .opacity(d.estimated ? 0.55 : 1)
                                .frame(height: max(4, 110 * v / maxV))
                        }
                    }
                    .frame(height: 110)
                    Text(d.date.plWeekdayShort)
                        .font(.system(size: 12, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Palette.claude : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Średnie zużycie wg dnia tygodnia.
struct WeekdayChart: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let data = model.weekdayAverages
        Chart(data) { d in
            BarMark(x: .value("Dzień", d.name), y: .value("%", d.avg))
                .foregroundStyle(Palette.gradient(Palette.violet.opacity(0.7), Palette.indigo))
                .cornerRadius(5)
                .annotation(position: .top) {
                    if d.samples > 0 {
                        Text(Fmt.pct1(d.avg)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
        }
        .chartYAxis(.hidden)
        .frame(height: 170)
    }
}

/// Szczyty zakończonych okien 5h.
struct FiveHourHistoryChart: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let wins = model.fiveHourWindows
        if wins.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "hourglass").font(.system(size: 28)).foregroundStyle(Palette.violet)
                Text("Jeszcze żadne okno 5h nie zakończyło się od początku zapisu.")
                    .font(.callout)
                if let next = model.usage?.fiveHour?.resetDate {
                    Text("Pierwsze zamknie się: \(Fmt.resetAt(next, now: model.now)).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170)
        } else {
            Chart {
                ForEach(wins, id: \.end) { w in
                    BarMark(x: .value("Koniec okna", w.end), y: .value("%", w.peak), width: .fixed(12))
                        .foregroundStyle(Palette.gradient(Fmt.color(w.peak).opacity(0.7), Fmt.color(w.peak)))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Limit", 100))
                    .foregroundStyle(Palette.coral.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { percentAxis([0, 50, 100]) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).hour().locale(pl))
                }
            }
            .frame(height: 200)
        }
    }
}

/// Kolory źródeł zużycia.
enum SourceColors {
    static func color(_ name: String, index: Int) -> Color {
        switch name {
        case "Claude Code": return Palette.claude
        case "Czaty": return Palette.blue
        case "Cowork": return Palette.violet
        default: return [Palette.teal, Palette.amber, Palette.slate][index % 3]
        }
    }
}

struct SourcesDonut: View {
    let sources: [SourceShare]
    var size: CGFloat = 170

    var body: some View {
        let total = sources.map(\.percent).reduce(0, +)
        ZStack {
            Chart(Array(sources.enumerated()), id: \.offset) { i, s in
                SectorMark(angle: .value("%", max(s.percent, total == 0 ? 1 : 0.0001)),
                           innerRadius: .ratio(0.64), angularInset: 2)
                    .cornerRadius(4)
                    .foregroundStyle(SourceColors.color(s.name, index: i))
            }
            if let top = sources.max(by: { $0.percent < $1.percent }), total > 0 {
                VStack(spacing: 0) {
                    Text("\(Int(top.percent))%").font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                    Text(top.name).font(.system(size: size * 0.075)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}


/// Spodziewane zużycie w kolejnych dniach do resetu (mediana symulacji).
struct ForecastDaysChart: View {
    let days: [ForecastDay]
    var height: CGFloat = 170
    @State private var grown = false

    var body: some View {
        let items = days.compactMap { d in DateFormatter.isoDay.date(from: d.date).map { (date: $0, d: d) } }
        let pace = 100.0 / 7
        let top = max((items.map(\.d.expected).max() ?? 1) * 1.15, pace * 1.15)
        let barArea = height - 40   // miejsce na podpis wartości i dnia
        ZStack(alignment: .bottom) {
            // linia równego tempa
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Line().stroke(Palette.slate.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                Spacer().frame(height: 20 + barArea * pace / top)
            }
            Text("równe tempo " + Fmt.pct1(pace) + "/dzień")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, 24 + barArea * pace / top)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                    VStack(spacing: 5) {
                        Text(Fmt.pct1(x.d.expected))
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.gradient(Fmt.color(x.d.expected * 7).opacity(0.9), Palette.violet))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)))
                            .frame(height: max(4, grown ? barArea * x.d.expected / top : 4))
                            .shadow(color: Palette.violet.opacity(0.35), radius: 5, y: 3)
                        Text(i == 0 ? "dziś" : x.date.plWeekdayShort)
                            .font(.system(size: 11.5, weight: i == 0 ? .bold : .regular))
                            .foregroundStyle(i == 0 ? Palette.claude : .secondary)
                            .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.3)) { grown = true } }
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}
