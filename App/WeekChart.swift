import Charts
import SwiftUI

private let pl = Locale(identifier: "pl_PL")

/// Kolory wykresu tygodnia.
enum WC {
    static let measured = Color(red: 0.10, green: 0.68, blue: 0.84)    // turkus — odczyty serwera
    static let estimate = Color(red: 0.10, green: 0.68, blue: 0.84).opacity(0.55)
    static let forecast = Color(red: 0.55, green: 0.42, blue: 0.97)    // fiolet — prognoza
    static let idle = Color(red: 0.55, green: 0.60, blue: 0.68)        // szary — przerwy
    static let hot = Color(red: 0.97, green: 0.36, blue: 0.32)         // czerwony — duże zużycie
    static let pace = Color(red: 0.95, green: 0.72, blue: 0.25)        // bursztyn — równe tempo
    static let limit = Color(red: 0.92, green: 0.26, blue: 0.30)
}

struct WeekPoint {
    var date: Date
    var value: Double
    var estimated: Bool
}

extension ReportModel {
    /// Oś czasu z kolektora + nowsze odczyty z historii (na żywo, co minutę).
    func computeWeekPoints() -> [WeekPoint] {
        guard let reset = usage?.weekly?.resetDate else { return [] }
        var pts: [WeekPoint] = (analytics?.weekTimeline?.points ?? []).compactMap { p in
            p.date.map { WeekPoint(date: $0, value: p.v, estimated: p.est) }
        }
        let last = pts.last?.date ?? .distantPast
        let real = history.filter { Self.sameMoment($0.wr, reset) && $0.t > last }
        pts += real.map { WeekPoint(date: $0.t, value: $0.w, estimated: false) }
        if let w = usage?.weekly, (pts.last?.date ?? .distantPast) < now.addingTimeInterval(-90) {
            pts.append(WeekPoint(date: now, value: w.percent, estimated: w.isEstimate))
        }
        // nigdy nie maleje
        var m = 0.0
        return pts.sorted { $0.date < $1.date }.map { p in
            m = max(m, p.value)
            return WeekPoint(date: p.date, value: m, estimated: p.estimated)
        }
    }
}

/// Przebieg tygodnia: odczyty, szacunek, przerwy, okresy dużego zużycia, równe tempo, prognoza.
struct WeekChart: View {
    @ObservedObject var model: ReportModel
    var height: CGFloat = 320

    var body: some View {
        let pts = model.weekPoints
        let tl = model.analytics?.weekTimeline
        let reset = model.usage?.weekly?.resetDate ?? model.now
        let start = model.weekStart ?? model.now.addingTimeInterval(-7 * 86400)
        let current = pts.last?.value ?? model.usage?.weekly?.percent ?? 0
        let fc = model.usage?.stats?.forecast
        let path = (fc?.path ?? []).compactMap { p in p.date.map { (date: $0, p: p) } }
        let maxY = max(124, (fc?.high ?? 0) + 15, current + 20)
        let estPts = estimatedSegment(pts)
        let realPts = pts.filter { !$0.estimated }
        let idle = (tl?.idle ?? []).filter { $0.startDate != nil && $0.endDate != nil }
        let hot = (tl?.intense ?? []).filter { $0.startDate != nil && $0.endDate != nil }
        let labeledHot = Set(hot.sorted { ($0.gain ?? 0) > ($1.gain ?? 0) }.prefix(3).map(\.id))

        VStack(alignment: .leading, spacing: 12) {
            Chart {
                // przerwy
                ForEach(idle) { s in
                    RectangleMark(xStart: .value("od", s.startDate!), xEnd: .value("do", s.endDate!),
                                  yStart: .value("d", 0), yEnd: .value("g", maxY))
                        .foregroundStyle(WC.idle.opacity(0.13))
                        .annotation(position: .overlay, alignment: .top, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            if (s.hours ?? 0) >= 6 {
                                bandLabel("moon.zzz.fill", hoursText(s.hours ?? 0), WC.idle)
                                    .padding(.top, 4)
                            }
                        }
                }
                // duże zużycie
                ForEach(hot) { s in
                    RectangleMark(xStart: .value("od", s.startDate!), xEnd: .value("do", s.endDate!),
                                  yStart: .value("d", 0), yEnd: .value("g", maxY))
                        .foregroundStyle(WC.hot.opacity(0.16))
                        .annotation(position: .overlay, alignment: .top, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            if labeledHot.contains(s.id) {
                                bandLabel("flame.fill", "+\(Fmt.pct1(s.gain ?? 0))", WC.hot)
                                    .padding(.top, 26)
                            }
                        }
                }
                // równe tempo: 0% na starcie → 100% przy resecie
                LineMark(x: .value("Czas", start), y: .value("%", 0.0), series: .value("s", "pace"))
                    .foregroundStyle(WC.pace.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                LineMark(x: .value("Czas", reset), y: .value("%", 100.0), series: .value("s", "pace"))
                    .foregroundStyle(WC.pace.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                PointMark(x: .value("Czas", start.addingTimeInterval(5.6 * 86400)), y: .value("%", 80.0))
                    .opacity(0)
                    .annotation(position: .topLeading, spacing: 2) {
                        Text("równe tempo (100% w 7 dni)")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(WC.pace)
                    }

                // szacunek z logów (przed pierwszym odczytem)
                ForEach(Array(estPts.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Czas", p.date), y: .value("%", p.value), series: .value("s", "estA"), stacking: .unstacked)
                        .foregroundStyle(LinearGradient(colors: [WC.measured.opacity(0.18), WC.measured.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Czas", p.date), y: .value("%", p.value), series: .value("s", "est"))
                        .foregroundStyle(WC.estimate)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
                }
                if let mid = estPts.dropFirst(estPts.count / 2).first, estPts.count > 3 {
                    PointMark(x: .value("Czas", mid.date), y: .value("%", mid.value)).opacity(0)
                        .annotation(position: .top, spacing: 6) {
                            Text("szacunek z logów").font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(WC.measured)
                        }
                }
                // odczyty serwera
                ForEach(Array(realPts.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Czas", p.date), y: .value("%", p.value), series: .value("s", "realA"), stacking: .unstacked)
                        .foregroundStyle(LinearGradient(colors: [WC.measured.opacity(0.35), WC.measured.opacity(0.04)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Czas", p.date), y: .value("%", p.value), series: .value("s", "real"))
                        .foregroundStyle(WC.measured)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if let first = realPts.first, !estPts.isEmpty {
                    PointMark(x: .value("Czas", first.date), y: .value("%", first.value))
                        .foregroundStyle(WC.measured)
                        .symbolSize(40)
                        .annotation(position: .topLeading, spacing: 4) {
                            Text("pierwszy odczyt").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                }

                // najszybsza godzina
                if let peak = tl?.peakHour, let e = peak.endDate, (peak.gain ?? 0) >= 1 {
                    PointMark(x: .value("Czas", e), y: .value("%", value(at: e, pts)))
                        .symbol { Image(systemName: "bolt.circle.fill").font(.system(size: 15)).foregroundStyle(WC.hot) }
                        .annotation(position: .topLeading, spacing: 2) {
                            Text("najszybsza godzina: +\(Fmt.pct1(peak.gain ?? 0))")
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(WC.hot)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(.background.opacity(0.85)))
                        }
                }

                // prognoza
                if let fc, path.count > 1 {
                    ForEach(Array(path.enumerated()), id: \.offset) { _, x in
                        AreaMark(x: .value("Czas", x.date), yStart: .value("od", x.p.low), yEnd: .value("do", x.p.high),
                                 series: .value("s", "band"))
                            .foregroundStyle(WC.forecast.opacity(0.17))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array(path.enumerated()), id: \.offset) { i, x in
                        LineMark(x: .value("Czas", x.date), y: .value("%", x.p.median), series: .value("s", "proj"))
                            .foregroundStyle(WC.forecast)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, dash: [6, 5]))
                            .interpolationMethod(.monotone)
                            .symbol { if i == path.count - 1 { Circle().fill(WC.forecast).frame(width: 9, height: 9) } }
                            .annotation(position: .topLeading, spacing: 4) {
                                if i == path.count - 1 {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("prognoza ~\(Int(fc.median.rounded()))%").font(.system(size: 11, weight: .bold))
                                        Text("zakres \(Fmt.range(fc.low, fc.high))").font(.system(size: 10))
                                    }
                                    .foregroundStyle(WC.forecast)
                                }
                            }
                    }
                }

                // teraz
                RuleMark(x: .value("Teraz", model.now))
                    .foregroundStyle(WC.measured.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Czas", model.now), y: .value("%", current))
                    .foregroundStyle(WC.measured)
                    .symbolSize(110)
                    .annotation(position: .top, spacing: 6) {
                        Text("teraz \(Int(current.rounded()))%")
                            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(WC.measured))
                    }

                // limit
                RuleMark(y: .value("Limit", 100))
                    .foregroundStyle(WC.limit.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                        Text("limit 100%").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(WC.limit)
                    }

            }
            .chartYScale(domain: 0...maxY)
            .chartXScale(domain: start...reset)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day().locale(pl), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))%") }
                }
            }
            // kursor w osobnej warstwie: ruch myszy odświeża tylko linię i dymek, nie cały wykres
            .chartOverlay { proxy in
                WeekHoverLayer(proxy: proxy, start: start, reset: reset) { h in
                    AnyView(tooltip(h, pts: pts, tl: tl, path: path))
                }
            }
            .frame(height: height)

            legend
            daysStrip(tl?.days ?? [], activeTotal: tl?.activeHours)
        }
    }

    // MARK: Części

    private func estimatedSegment(_ pts: [WeekPoint]) -> [WeekPoint] {
        guard let firstReal = pts.firstIndex(where: { !$0.estimated }) else { return pts }
        let est = Array(pts[..<firstReal])
        return est.isEmpty ? [] : est + [pts[firstReal]]   // łączy się z pierwszym odczytem
    }

    private func value(at t: Date, _ pts: [WeekPoint]) -> Double {
        pts.last { $0.date <= t }?.value ?? 0
    }

    private func hoursText(_ h: Double) -> String {
        if h < 1 { return "\(Int((h * 60).rounded())) min" }
        let r = (h * 2).rounded() / 2
        return r == r.rounded() ? "\(Int(r)) h" : String(format: "%.1f h", r).replacingOccurrences(of: ".", with: ",")
    }

    private func bandLabel(_ icon: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .bold))
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(.background.opacity(0.8)))
        .fixedSize()
    }

    @ViewBuilder
    private func tooltip(_ t: Date, pts: [WeekPoint], tl: WeekTimeline?, path: [(date: Date, p: ForecastPoint)]) -> some View {
        let past = t <= model.now
        VStack(alignment: .leading, spacing: 4) {
            Text(t.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(pl)))
                .font(.system(size: 11.5, weight: .semibold))
            if past {
                let v = value(at: t, pts)
                let hourAgo = value(at: t.addingTimeInterval(-3600), pts)
                let est = pts.last { $0.date <= t }?.estimated ?? false
                HStack(spacing: 6) {
                    Circle().fill(WC.measured).frame(width: 7, height: 7)
                    Text("zużyte: \(Fmt.pct1(v)) limitu").font(.system(size: 12, weight: .bold)).monospacedDigit()
                }
                Text(est ? "szacunek z lokalnych logów" : "odczyt z serwera").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Text("w poprzedniej godzinie: +\(Fmt.pct1(max(0, v - hourAgo)))").font(.system(size: 11)).monospacedDigit()
                if let s = tl?.idle?.first(where: { span($0, contains: t) }) {
                    Label("przerwa \(hoursText(s.hours ?? 0))", systemImage: "moon.zzz.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(WC.idle)
                }
                if let s = tl?.intense?.first(where: { span($0, contains: t) }) {
                    Label("duże zużycie: +\(Fmt.pct1(s.gain ?? 0)) w \(hoursText(s.hours ?? 1)) (\(Fmt.pct1(s.perHour ?? 0))/h)",
                          systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(WC.hot)
                }
                if let d = tl?.days?.first(where: { $0.day.map { Calendar.current.isDate($0, inSameDayAs: t) } ?? false }) {
                    Text("cały dzień: +\(Fmt.pct1(d.gain)) · \(hoursText(d.activeHours)) pracy")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else if let seg = forecastAt(t, path) {
                HStack(spacing: 6) {
                    Circle().fill(WC.forecast).frame(width: 7, height: 7)
                    Text("prognoza: ~\(Int(seg.median.rounded()))%").font(.system(size: 12, weight: .bold))
                }
                Text("zakres 10–90%: \(Fmt.range(seg.low, seg.high))").font(.system(size: 11))
                let paceV = 100 * t.timeIntervalSince(model.weekStart ?? t) / (7 * 86400)
                Text("równe tempo w tym momencie: \(Int(paceV.rounded()))%").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3))
        .padding(.top, 4)
    }

    private func span(_ s: TimelineSpan, contains t: Date) -> Bool {
        guard let a = s.startDate, let b = s.endDate else { return false }
        return a <= t && t <= b
    }

    private func forecastAt(_ t: Date, _ path: [(date: Date, p: ForecastPoint)]) -> (median: Double, low: Double, high: Double)? {
        guard let i = path.firstIndex(where: { $0.date >= t }) else { return path.last.map { ($0.p.median, $0.p.low, $0.p.high) } }
        if i == 0 { return (path[0].p.median, path[0].p.low, path[0].p.high) }
        let a = path[i - 1], b = path[i]
        let f = t.timeIntervalSince(a.date) / max(1, b.date.timeIntervalSince(a.date))
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return (lerp(a.p.median, b.p.median), lerp(a.p.low, b.p.low), lerp(a.p.high, b.p.high))
    }

    private var legend: some View {
        let items: [(AnyView, String)] = [
            (AnyView(Capsule().fill(WC.measured).frame(width: 18, height: 3)), "odczyty z serwera"),
            (AnyView(dashed(WC.measured)), "szacunek z logów (przed pierwszym odczytem)"),
            (AnyView(dashed(WC.pace)), "równe tempo — 100% dokładnie przy resecie"),
            (AnyView(ZStack { RoundedRectangle(cornerRadius: 2).fill(WC.forecast.opacity(0.25)); dashed(WC.forecast) }.frame(width: 18, height: 10)), "prognoza i zakres 10–90%"),
            (AnyView(RoundedRectangle(cornerRadius: 2).fill(WC.idle.opacity(0.35)).frame(width: 14, height: 10)), "przerwa ≥ 3 h (🌙 długość)"),
            (AnyView(RoundedRectangle(cornerRadius: 2).fill(WC.hot.opacity(0.4)).frame(width: 14, height: 10)), "duże zużycie ≥ 2%/h (🔥 przyrost)"),
            (AnyView(Image(systemName: "bolt.circle.fill").font(.system(size: 12)).foregroundStyle(WC.hot)), "najszybsza godzina tygodnia"),
            (AnyView(Image(systemName: "cursorarrow.rays").font(.system(size: 12)).foregroundStyle(.secondary)), "najedź kursorem — szczegóły chwili"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 7) {
                    it.0.frame(width: 20)
                    Text(it.1).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dashed(_ c: Color) -> some View {
        Path { p in p.move(to: CGPoint(x: 0, y: 1.5)); p.addLine(to: CGPoint(x: 18, y: 1.5)) }
            .stroke(c, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
            .frame(width: 18, height: 3)
    }

    private func daysStrip(_ days: [TimelineDay], activeTotal: Double?) -> some View {
        let maxG = max(1, days.map(\.gain).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dzień po dniu w tym okresie limitu").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let a = activeTotal {
                    Text("łącznie \(hoursText(a)) aktywnej pracy").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(days) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.day.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(pl)) } ?? d.date)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text("+\(Fmt.pct1(d.gain))").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(d.gain > 100.0 / 7 ? WC.hot : WC.measured)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(WC.measured.opacity(0.12))
                                Capsule().fill(d.gain > 100.0 / 7 ? WC.hot : WC.measured).frame(width: max(3, g.size.width * d.gain / maxG))
                            }
                        }
                        .frame(height: 5)
                        Text("\(hoursText(d.activeHours)) pracy\(d.est ? " · szac." : "")\(d.partial ? " · trwa" : "")")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.045)))
                }
                ForEach(0..<max(0, 7 - days.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(maxWidth: .infinity).frame(height: 78)
                }
            }
        }
    }
}


/// Warstwa kursora nad wykresem tygodnia — ma własny stan, więc ruch myszy
/// nie wymusza przeliczania i ponownego rysowania setek znaczników wykresu.
private struct WeekHoverLayer: View {
    let proxy: ChartProxy
    let start: Date
    let reset: Date
    let tooltip: (Date) -> AnyView
    @State private var hover: Date? = nil

    var body: some View {
        GeometryReader { g in
            let plot = proxy.plotFrame.map { g[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let d = proxy.value(atX: loc.x - plot.minX, as: Date.self).map { min(max($0, start), reset) }
                            // aktualizuj co najmniej co ~10 min osi — mniej przeliczeń przy drobnych ruchach
                            if let d, let old = hover, abs(d.timeIntervalSince(old)) < 600 { return }
                            hover = d
                        case .ended:
                            hover = nil
                        }
                    }
                if let h = hover, let x = proxy.position(forX: h) {
                    Rectangle().fill(Color.primary.opacity(0.45))
                        .frame(width: 1, height: plot.height)
                        .offset(x: plot.minX + x, y: plot.minY)
                        .allowsHitTesting(false)
                    tooltip(h)
                        .fixedSize()
                        .offset(x: min(max(0, plot.minX + x - 125), max(0, g.size.width - 252)), y: plot.minY + 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
