import SwiftUI

// MARK: - Przegląd

struct OverviewTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let u = model.usage
        let s = u?.stats
        PageStack {
            hero
            HStack(alignment: .top, spacing: 16) {
                if let w = u?.fiveHour { gaugeCard(w, title: "Okno 5h", icon: "clock.fill", tint: Palette.violet) }
                if let w = u?.weekly { gaugeCard(w, title: "Limit tygodniowy", icon: "calendar", tint: Palette.blue) }
            }
            HStack(spacing: 14) {
                KPITile(title: "Prognoza tygodnia",
                        value: s?.projectedWeekly.map { "~\(Int($0.rounded()))%" } ?? "—",
                        detail: s?.forecast.map { "zakres \(Fmt.range($0.low, $0.high))" } ?? "przy obecnym tempie",
                        icon: "chart.line.uptrend.xyaxis",
                        colors: (Palette.claude, Palette.coral))
                KPITile(title: "Budżet na dzień",
                        value: model.dailyBudget.map(Fmt.pct1) ?? "—",
                        detail: "żeby zmieścić się do resetu", icon: "gauge.with.dots.needle.33percent",
                        colors: (Palette.teal, Palette.mint))
                KPITile(title: "Średnio dziennie",
                        value: s?.avgDaily30.map(Fmt.pct1) ?? "—",
                        detail: "z ostatnich \(s?.daysCounted ?? 0) dni", icon: "calendar.badge.clock",
                        colors: (Palette.indigo, Palette.violet))
                KPITile(title: "Okna 5h",
                        value: s?.fiveHour?.avgPeak.map { "\(Int($0.rounded()))%" } ?? "—",
                        detail: (s?.fiveHour?.windows ?? 0) > 0 ? "średni szczyt · limit \(s?.fiveHour?.limitHits ?? 0)×" : "zbieram dane",
                        icon: "hourglass", colors: (Palette.blue, Palette.indigo))
            }
            Card(title: "Ten tydzień", subtitle: "% limitu tygodniowego od resetu · najedź kursorem, by zobaczyć szczegóły dowolnej chwili",
                 icon: "chart.xyaxis.line", tint: Palette.claude) {
                WeekChart(model: model, height: 300)
            }
            if let a = model.analytics {
                InsightsCard(insights: a.insights)
                ThirtyDaysCard(a: a)
            }
        }
    }

    var hero: some View {
        let proj = model.usage?.stats?.projectedWeekly ?? 0
        let chance = model.usage?.stats?.forecast?.chanceOver100 ?? (proj >= 100 ? 1 : 0)
        let (status, color, icon): (String, Color, String) =
            chance >= 0.5 ? ("Ryzyko przekroczenia", Palette.coral, "exclamationmark.triangle.fill")
            : (chance >= 0.15 || proj >= 80) ? ("Niewielki zapas", Palette.amber, "exclamationmark.circle.fill")
            : ("Wszystko w normie", Palette.mint, "checkmark.seal.fill")
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                    Text(status).font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.55)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
                Text(greeting).font(.system(size: 28, weight: .bold))
                Text(model.headline).font(.system(size: 14)).opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            FloatingBurst(size: 104)
                .padding(.trailing, 10)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(
            ZStack {
                Palette.claudeGradient
                Circle().fill(.white.opacity(0.08)).frame(width: 260).offset(x: 300, y: -90)
                Circle().fill(.white.opacity(0.06)).frame(width: 180).offset(x: 380, y: 70)
            }
        )
        .overlay(
            // szklany połysk i krawędź
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: Palette.claude.opacity(0.45), radius: 18, y: 8)
        .tilt3D(22, maxAngle: 3)
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: model.now)
        switch h {
        case 5..<12: return "Dzień dobry"
        case 12..<18: return "Dobrego popołudnia"
        default: return "Dobry wieczór"
        }
    }

    func gaugeCard(_ w: LimitWindow, title: String, icon: String, tint: Color) -> some View {
        Card(title: title, icon: icon, tint: tint) {
            HStack(spacing: 22) {
                RingGauge(percent: w.percent, size: 128, lineWidth: 14, label: w.isEstimate ? "≈ szacunek" : "wykorzystano")
                VStack(alignment: .leading, spacing: 10) {
                    stat("Pozostało", "\(Int(max(0, 100 - w.percent).rounded()))%", Fmt.color(w.percent))
                    stat("Reset za", Fmt.countdown(w.resetDate, now: model.now), .primary)
                    Pill(text: Fmt.resetAt(w.resetDate, now: model.now), color: tint, icon: "arrow.counterclockwise")
                }
                Spacer(minLength: 0)
            }
        }
    }

    func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
    }
}

// MARK: - Tydzień

struct WeekTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let w = model.usage?.weekly
        let s = model.usage?.stats
        PageStack {
            PageHeader(title: "Tydzień", subtitle: weekRange, icon: "calendar", tint: Palette.blue)
            HStack(spacing: 14) {
                KPITile(title: "Wykorzystano", value: w.map(\.shown) ?? "—",
                        detail: w?.isEstimate == true ? "szacunek na żywo" : "limitu tygodniowego", icon: "chart.pie.fill", colors: (Palette.blue, Palette.indigo))
                KPITile(title: "Pozostało", value: w.map { "\(Int(max(0, 100 - $0.percent).rounded()))%" } ?? "—",
                        detail: "reset \(Fmt.resetAt(w?.resetDate, now: model.now))", icon: "battery.75percent",
                        colors: (Palette.teal, Palette.mint))
                KPITile(title: "Średnio dziennie", value: s?.weekAvgPerDay.map(Fmt.pct1) ?? "—",
                        detail: "w tym tygodniu", icon: "speedometer", colors: (Palette.violet, Palette.pink))
                KPITile(title: "Prognoza", value: s?.projectedWeekly.map { "~\(Int($0.rounded()))%" } ?? "—",
                        detail: s?.forecast.map { "zakres \(Fmt.range($0.low, $0.high))" } ?? "na koniec tygodnia",
                        icon: "chart.line.uptrend.xyaxis",
                        colors: (Palette.claude, Palette.coral))
            }
            Card(title: "Przebieg tygodnia", subtitle: "% limitu tygodniowego od resetu · przerwy, intensywna praca i prognoza · najedź kursorem po szczegóły",
                 icon: "chart.xyaxis.line", tint: Palette.claude) {
                WeekChart(model: model, height: 360)
            }
            if let fc = s?.forecast {
                ForecastCard(model: model, fc: fc)
            }
            PaceCard(model: model)
            if let f = s?.forecast?.weekdayFactors {
                WeekdayProfileCard(factors: f)
            }
            Card(title: "Dzień po dniu", subtitle: "zużycie limitu tygodniowego w poszczególne dni · jaśniejsze = szacunek",
                 icon: "chart.bar.fill", tint: Palette.blue) {
                ThisWeekDaysChart(model: model)
            }
            WeeksCompareCard(model: model)
        }
    }

    var weekRange: String {
        guard let s = model.weekStart, let e = model.usage?.weekly?.resetDate else { return "" }
        return "Okres limitu: \(s.plDayMonth) – \(e.addingTimeInterval(-60).plDayMonth)"
    }
}

// MARK: - Okna 5h

struct FiveHourTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let w = model.usage?.fiveHour
        let f = model.usage?.stats?.fiveHour
        let maxPeak = model.fiveHourWindows.map(\.peak).max()
        PageStack {
            PageHeader(title: "Okna 5h", subtitle: "Limit odnawiany co 5 godzin od pierwszej wiadomości",
                       icon: "clock.fill", tint: Palette.violet)
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Teraz", icon: "timer", tint: Palette.violet) {
                    VStack(spacing: 14) {
                        RingGauge(percent: w?.percent ?? 0, size: 150, lineWidth: 16, label: w?.isEstimate == true ? "≈ szacunek" : "wykorzystano")
                        Pill(text: "reset za \(Fmt.countdown(w?.resetDate, now: model.now))", color: Palette.violet,
                             icon: "arrow.counterclockwise")
                        Text("o \(Fmt.resetAt(w?.resetDate, now: model.now))").font(.caption).foregroundStyle(.secondary)
                        if let f5 = model.usage?.stats?.fiveHourForecast, (w?.percent ?? 0) < 100 {
                            FiveHourForecastBadge(f: f5, now: model.now)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 260)
                Card(title: "Bieżące okno", subtitle: "jak rosło wykorzystanie", icon: "waveform.path.ecg", tint: Palette.indigo) {
                    FiveHourNowChart(model: model, height: 230)
                }
            }
            HStack(spacing: 14) {
                KPITile(title: "Zakończone okna", value: "\(f?.windows ?? 0)", detail: "w ostatnich 30 dniach",
                        icon: "square.stack.3d.up.fill", colors: (Palette.violet, Palette.indigo))
                KPITile(title: "Średni szczyt", value: f?.avgPeak.map { "\(Int($0.rounded()))%" } ?? "—",
                        detail: "wykorzystania okna", icon: "mountain.2.fill", colors: (Palette.blue, Palette.teal))
                KPITile(title: "Najwyższy szczyt", value: maxPeak.map { "\(Int($0.rounded()))%" } ?? "—",
                        detail: "rekord", icon: "flame.fill", colors: (Palette.amber, Palette.claude))
                KPITile(title: "Limit osiągnięty", value: "\(f?.limitHits ?? 0)×", detail: "okna wykorzystane w 100%",
                        icon: "exclamationmark.octagon.fill", colors: (Palette.coral, Palette.pink))
            }
            Card(title: "Historia okien", subtitle: "szczyt każdego zakończonego okna 5h",
                 icon: "chart.bar.doc.horizontal.fill", tint: Palette.violet) {
                FiveHourHistoryChart(model: model)
            }
            if let a = model.analytics {
                FiveHourAdvancedCard(model: model, a: a)
                WindowStartsCard(starts: a.fiveHourStarts)
            }
        }
    }
}

// MARK: - Historia

struct HistoryTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let s = model.usage?.stats
        PageStack {
            PageHeader(title: "Historia", subtitle: "Ostatnie 30 dni · dzienne zużycie jako % limitu tygodniowego",
                       icon: "chart.bar.xaxis", tint: Palette.teal)
            HStack(spacing: 14) {
                KPITile(title: "Średnio dziennie", value: s?.avgDaily30.map(Fmt.pct1) ?? "—",
                        detail: "z \(s?.daysCounted ?? 0) dni", icon: "sum", colors: (Palette.teal, Palette.blue))
                KPITile(title: "Najintensywniejszy", value: model.peakDay.map { Fmt.pct1($0.pct) } ?? "—",
                        detail: model.peakDay.map { $0.date.plDayMonth } ?? "", icon: "flame.fill",
                        colors: (Palette.claude, Palette.coral))
                KPITile(title: "Najspokojniejszy", value: model.calmestDay.map { Fmt.pct1($0.pct) } ?? "—",
                        detail: model.calmestDay.map { $0.date.plDayMonth } ?? "", icon: "leaf.fill",
                        colors: (Palette.mint, Palette.teal))
                KPITile(title: "Powyżej tempa", value: "\(model.daysAbovePace)",
                        detail: "z \(model.activeDays) aktywnych dni", icon: "hare.fill",
                        colors: (Palette.violet, Palette.pink))
            }
            Card(title: "Dzienne zużycie", subtitle: "jaśniejsze słupki = szacunek z lokalnych logów Claude Code",
                 icon: "chart.bar.fill", tint: Palette.teal) {
                Daily30Chart(model: model, height: 250)
            }
            Card(title: "Rytm tygodnia", subtitle: "średnie zużycie w poszczególne dni tygodnia",
                 icon: "waveform", tint: Palette.indigo) {
                WeekdayChart(model: model)
            }
            HistoryStatsCard(model: model)
            if let a = model.analytics {
                HeatmapCard(matrix: a.heatmap, responses: a.heatmapResponses, k: a.k)
                if let k = a.k { DailyValueCard(daily: a.daily, k: k) }
            }
        }
    }
}

// MARK: - Źródła

struct SourcesTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        let sources = model.usage?.stats?.sources ?? []
        PageStack {
            PageHeader(title: "Źródła i modele", subtitle: "Skąd pochodzi zużycie: aplikacje, modele, tokeny i sposób pracy",
                       icon: "chart.pie.fill", tint: Palette.amber)
            Card(title: "Podział w tym tygodniu", subtitle: "według danych z serwera Anthropic",
                 icon: "circle.hexagongrid.fill", tint: Palette.amber) {
                HStack(spacing: 36) {
                    SourcesDonut(sources: sources, size: 200)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { i, s in
                            let c = SourceColors.color(s.name, index: i)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Circle().fill(c).frame(width: 10, height: 10)
                                    Text(s.name).font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    Text("\(Int(s.percent))%").font(.system(size: 16, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(c.opacity(0.15))
                                        Capsule().fill(c.gradient).frame(width: max(6, g.size.width * s.percent / 100))
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            if let a = model.analytics {
                ModelsCard(a: a)
                if let t = a.d30 { TokenBreakdownCard(c: t) }
                GroupsCard(a: a)
            }
            Card(title: "Co oznaczają źródła", icon: "questionmark.circle.fill", tint: Palette.slate) {
                VStack(alignment: .leading, spacing: 8) {
                    legend("Claude Code", "praca w terminalu i w aplikacji desktopowej (zakładka Code)")
                    legend("Czaty", "rozmowy na claude.ai i w aplikacji Claude")
                    legend("Cowork", "zadania wykonywane przez Claude w trybie Cowork")
                    legend("Inne", "pozostałe integracje i aplikacje")
                }
            }
        }
    }

    func legend(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.system(size: 13, weight: .semibold)).frame(width: 100, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}


// MARK: - Prognoza

struct ForecastCard: View {
    @ObservedObject var model: ReportModel
    let fc: WeekForecast

    var body: some View {
        let c = Fmt.color(fc.median)
        Card(title: "Prognoza na koniec tygodnia",
             subtitle: "symulacja \(fc.sampleDays ?? 0) ostatnich dni · rytm dni tygodnia · pora dnia",
             icon: "wand.and.stars", tint: Palette.indigo) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("najbardziej prawdopodobnie").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("~\(Int(fc.median.rounded()))%")
                            .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(c)
                            .contentTransition(.numericText())
                            .animation(.smooth, value: fc.median)
                    }
                    RangeBar(low: fc.low, median: fc.median, high: fc.high)
                        .frame(width: 250)
                    HStack(spacing: 8) {
                        Pill(text: "szansa przekroczenia \(Fmt.chance(fc.chanceOver100))",
                             color: fc.chanceOver100 >= 0.5 ? Palette.coral : fc.chanceOver100 >= 0.15 ? Palette.amber : Palette.mint,
                             icon: "dice.fill")
                    }
                    Text(verdict).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 250, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spodziewane zużycie w kolejne dni").font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForecastDaysChart(days: fc.days)
                }
            }
            if let lin = model.usage?.stats?.linearWeekly {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Prosta proporcja (dotychczasowe tempo × 7 dni) dałaby ~\(Int(lin.rounded()))%. Ta prognoza uwzględnia, że w różne dni i o różnych porach pracujesz z różną intensywnością.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
    }

    var verdict: String {
        if let hit = fc.hitDate {
            return "W typowym scenariuszu limit skończy się \(Fmt.resetAt(hit, now: model.now)) — przed resetem."
        }
        let spare = 100 - fc.high
        if spare > 0 {
            return "Nawet w intensywnym scenariuszu (90. percentyl) zostanie ok. \(Int(spare.rounded()))% zapasu."
        }
        return "W typowym scenariuszu zmieścisz się, ale intensywny tydzień może wyczerpać limit."
    }
}

/// Pasek zakresu 10–90% z zaznaczoną medianą, na skali 0–100%.
struct RangeBar: View {
    let low: Double
    let median: Double
    let high: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let x = { (v: Double) in w * min(max(v, 0), 110) / 110 }
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [Fmt.color(low), Fmt.color(high)], startPoint: .leading, endPoint: .trailing))
                        .opacity(0.55)
                        .frame(width: max(8, x(high) - x(low)), height: 10)
                        .offset(x: x(low))
                    Rectangle().fill(Palette.coral).frame(width: 1.5, height: 16).offset(x: x(100))
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Fmt.color(median), lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: x(median) - 7)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text("ostrożnie \(Fmt.percent(low))")
                Spacer()
                Text("intensywnie \(Fmt.percent(high))")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct FiveHourForecastBadge: View {
    let f: FiveHourForecast
    let now: Date

    var body: some View {
        VStack(spacing: 3) {
            if let hit = f.hitDate {
                Label("limit skończy się ok. \(hit.formatted(date: .omitted, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.coral)
            } else {
                Label("starczy do resetu · ~\(Int(f.projected.rounded()))% na koniec", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.mint)
            }
            Text("tempo z ostatniej godziny: \(Fmt.pct1(f.ratePerHour))/h")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}


// MARK: - Projekty i sesje

struct ProjectsTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        PageStack {
            PageHeader(title: "Projekty i sesje", subtitle: "Gdzie i jak pracujesz z Claude Code · ostatnie 30 dni",
                       icon: "folder.fill", tint: Palette.pink)
            if let a = model.analytics {
                HStack(spacing: 14) {
                    KPITile(title: "Projekty", value: "\(a.projectCount)", detail: "aktywnych w 30 dni",
                            icon: "folder.fill", colors: (Palette.amber, Palette.claude))
                    KPITile(title: "Sesje", value: "\(a.sessions.count)", detail: "\(Int(a.sessions.totalActiveHours.rounded())) h aktywnej pracy",
                            icon: "bubble.left.and.bubble.right.fill", colors: (Palette.blue, Palette.indigo))
                    KPITile(title: "Wywołania narzędzi", value: Fmt.tokens(a.toolTotal), detail: "\(a.tools.count) rodzajów",
                            icon: "wrench.and.screwdriver.fill", colors: (Palette.teal, Palette.mint))
                    KPITile(title: "Dziś", value: a.limit(a.today?.cost ?? 0),
                            detail: "limitu tyg. · \(a.today?.responses ?? 0) odpowiedzi",
                            icon: "sun.max.fill", colors: (Palette.violet, Palette.pink))
                }
                ProjectsCard(a: a)
                SessionsCard(a: a)
                ToolsCard(a: a)
            } else {
                EmptyNote(text: "Analiza lokalnych logów jeszcze się nie wykonała — pojawi się w ciągu kilku minut.")
            }
        }
    }
}
