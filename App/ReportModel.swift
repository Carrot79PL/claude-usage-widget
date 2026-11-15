import Foundation
import SwiftUI
import WidgetKit

struct HistoryPoint: Identifiable {
    let t: Date
    let w: Double
    let wr: Date?
    let h: Double?
    let hr: Date?
    var id: Date { t }
}

struct DayValue: Identifiable {
    let date: Date
    let pct: Double
    let estimated: Bool
    var id: Date { date }
}

struct WeekdayAverage: Identifiable {
    let index: Int      // 0 = poniedziałek
    let name: String
    let avg: Double
    let samples: Int
    var id: Int { index }
}

/// Wynik wczytania plików w tle; nil = plik się nie zmienił.
struct DataSnapshot {
    var usage: Usage?
    var history: [HistoryPoint]?
    var analytics: Analytics?
    var stamps: [String: Date]
}

@MainActor
final class ReportModel: ObservableObject {
    @Published private(set) var usage: Usage?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var analytics: Analytics?
    @Published var now = Date()

    // Wartości pochodne — liczone raz po zmianie danych, a nie przy każdym rysowaniu widoku.
    @Published private(set) var days30: [DayValue] = []
    @Published private(set) var completeDays: [DayValue] = []
    @Published private(set) var weekPoints: [WeekPoint] = []
    @Published private(set) var fiveHourSeries: [HistoryPoint] = []

    private var timer: Timer?
    private var stamps: [String: Date] = [:]
    private var loading = false

    /// Tempo, przy którym cały limit tygodniowy kończy się dokładnie w tydzień.
    static let pacePerDay = 100.0 / 7

    init(autoRefresh: Bool = true) {
        apply(Self.readSnapshot(previous: [:]))
        guard autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        timer?.tolerance = 10   // pozwala systemowi grupować wybudzenia (oszczędza energię)
    }

    /// Wczytuje pliki na wątku w tle; parsuje tylko te, które się zmieniły.
    func reload() {
        now = .now
        guard !loading else { return }
        loading = true
        let prev = stamps
        Task.detached(priority: .utility) {
            let snap = ReportModel.readSnapshot(previous: prev)
            await MainActor.run { self.apply(snap) }
        }
    }

    private func apply(_ s: DataSnapshot) {
        loading = false
        stamps = s.stamps
        if let u = s.usage { usage = u }
        if let h = s.history { history = h }
        if let a = s.analytics { analytics = a }
        recomputeDerived()
    }

    nonisolated static func readSnapshot(previous: [String: Date]) -> DataSnapshot {
        let dir = dataDirectory
        var stamps: [String: Date] = [:]
        func changed(_ name: String) -> Bool {
            let d = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)[.modificationDate]) as? Date
            stamps[name] = d ?? .distantPast
            return d == nil || previous[name] != d
        }
        var s = DataSnapshot(stamps: [:])
        if changed("usage.json") { s.usage = UsageStore.load() }
        if changed("history.jsonl") { s.history = loadHistory() }
        if changed("analytics.json") { s.analytics = Analytics.load(from: dir) }
        s.stamps = stamps
        return s
    }

    private func recomputeDerived() {
        let d30: [DayValue] = (usage?.stats?.daily30 ?? []).compactMap { d in
            guard let date = DateFormatter.isoDay.date(from: d.date), let pct = d.pct else { return nil }
            return DayValue(date: date, pct: pct, estimated: d.estimated)
        }
        let today = Calendar.current.startOfDay(for: now)
        days30 = d30
        completeDays = d30.filter { $0.date < today }
        if let r = usage?.fiveHour?.resetDate {
            fiveHourSeries = history.filter { Self.sameMoment($0.hr, r) }
        } else {
            fiveHourSeries = []
        }
        weekPoints = computeWeekPoints()
    }

    /// Uruchamia od razu zadanie w tle, które pobiera świeże dane z serwera.
    func fetchNow() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "gui/\(getuid())/pl.claudeusage.collector"]
        try? p.run()
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.reload() }
    }

    nonisolated static var dataDirectory: URL { UsageStore.fileURL.deletingLastPathComponent() }

    nonisolated static func loadHistory() -> [HistoryPoint] {
        let url = dataDirectory.appendingPathComponent("history.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let t = Fmt.date(o["t"] as? String), let w = o["w"] as? Double else { return nil }
            return HistoryPoint(t: t, w: w, wr: Fmt.date(o["wr"] as? String),
                                h: o["h"] as? Double, hr: Fmt.date(o["hr"] as? String))
        }
    }

    nonisolated static func sameMoment(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) < 600
    }

    // MARK: Tydzień

    var weekStart: Date? { usage?.weekly?.resetDate?.addingTimeInterval(-7 * 86400) }

    /// Siedem dni bieżącego tygodnia limitów (przyszłe dni = nil).
    var thisWeekDays: [(date: Date, pct: Double?, estimated: Bool)] {
        guard let start = weekStart else { return [] }
        let cal = Calendar.current
        let first = cal.startOfDay(for: start.addingTimeInterval(60))
        let byDay = Dictionary(uniqueKeysWithValues: days30.map { (cal.startOfDay(for: $0.date), $0) })
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: first)!
            if d > now { return (d, nil, false) }
            let v = byDay[d]
            return (d, v?.pct ?? 0, v?.estimated ?? false)
        }
    }

    var dailyBudget: Double? {
        guard let w = usage?.weekly, let r = w.resetDate else { return nil }
        let days = r.timeIntervalSince(now) / 86400
        guard days > 0.1 else { return nil }
        return max(0, 100 - w.percent) / days
    }

    // MARK: Okno 5h

    var fiveHourWindows: [(end: Date, peak: Double)] {
        (usage?.stats?.fiveHourWindows ?? []).compactMap { w in w.endDate.map { (end: $0, peak: w.peak) } }
    }

    // MARK: Historia 30 dni

    var peakDay: DayValue? { completeDays.max { $0.pct < $1.pct } }
    var calmestDay: DayValue? { completeDays.filter { $0.pct > 0.5 }.min { $0.pct < $1.pct } }
    var daysAbovePace: Int { completeDays.filter { $0.pct > Self.pacePerDay }.count }
    var activeDays: Int { completeDays.filter { $0.pct > 0.5 }.count }

    var weekdayAverages: [WeekdayAverage] {
        let names = ["pon.", "wt.", "śr.", "czw.", "pt.", "sob.", "niedz."]
        let cal = Calendar(identifier: .iso8601)
        var sums = Array(repeating: 0.0, count: 7), counts = Array(repeating: 0, count: 7)
        for d in completeDays {
            let wd = (cal.component(.weekday, from: d.date) + 5) % 7   // pon=0
            sums[wd] += d.pct
            counts[wd] += 1
        }
        return (0..<7).map { WeekdayAverage(index: $0, name: names[$0],
                                            avg: counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : 0,
                                            samples: counts[$0]) }
    }

    // MARK: Podsumowanie słowne

    var headline: String {
        guard let w = usage?.weekly else { return "Brak danych o limitach." }
        let used = Int(w.percent.rounded())
        guard let p = usage?.stats?.projectedWeekly else {
            return "Wykorzystano \(used)% limitu tygodniowego."
        }
        let proj = Int(p.rounded())
        if let fc = usage?.stats?.forecast {
            let range = Fmt.range(fc.low, fc.high)
            if fc.chanceOver100 >= 0.5 {
                return "Wykorzystano \(used)% limitu tygodniowego. Prognoza ~\(proj)% (\(range)) — limit najpewniej skończy się przed resetem, warto zwolnić."
            } else if fc.chanceOver100 >= 0.15 || p >= 80 {
                return "Wykorzystano \(used)% limitu tygodniowego. Prognoza ~\(proj)% (\(range)), szansa przekroczenia \(Fmt.chance(fc.chanceOver100)) — zapas jest niewielki."
            }
            return "Wykorzystano \(used)% limitu tygodniowego. Prognoza ~\(proj)% (\(range)) na koniec tygodnia — spokojnie się mieścisz."
        }
        if p >= 100 {
            return "Wykorzystano \(used)% limitu tygodniowego. W tym tempie limit skończy się przed resetem (~\(proj)%) — warto zwolnić."
        } else if p >= 80 {
            return "Wykorzystano \(used)% limitu tygodniowego. Prognoza ~\(proj)% — mieścisz się, ale z niewielkim zapasem."
        }
        return "Wykorzystano \(used)% limitu tygodniowego. Prognoza ~\(proj)% na koniec tygodnia — spokojnie się mieścisz."
    }
}

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

extension Date {
    var plDayMonth: String {
        formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pl_PL")))
    }

    var plWeekdayShort: String {
        formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pl_PL")))
    }
}
