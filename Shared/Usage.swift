import Foundation
import SwiftUI

struct LimitWindow: Codable, Identifiable {
    var key: String
    var label: String
    var percent: Double
    var resetsAt: String?
    /// Szacunek na żywo: ostatni odczyt serwera + zużycie z logów Claude Code od tamtej chwili.
    var estimated: Bool? = nil
    var serverPercent: Double? = nil
    var serverAt: String? = nil
    var liveAdded: Double? = nil
    var id: String { key }

    var resetDate: Date? { Fmt.date(resetsAt) }
    var isEstimate: Bool { estimated == true }
    var serverDate: Date? { Fmt.date(serverAt) }
    /// „37%” albo „≈37%” dla szacunku.
    var shown: String { (isEstimate ? "≈" : "") + Fmt.percent(percent) }
}

struct DailyUse: Codable, Identifiable {
    var date: String
    var pct: Double?
    var estimated: Bool
    var id: String { date }
}

struct FiveHourStats: Codable {
    var windows: Int
    var avgPeak: Double?
    var limitHits: Int
}

struct SourceShare: Codable, Identifiable {
    var name: String
    var percent: Double
    var id: String { name }
}

struct ForecastPoint: Codable {
    var t: String
    var median: Double
    var low: Double
    var high: Double
    var date: Date? { Fmt.date(t) }
}

struct ForecastDay: Codable {
    var date: String
    var expected: Double
    var share: Double?
}

/// Prognoza tygodnia z symulacji: mediana, zakres 10–90% i szansa przekroczenia limitu.
struct WeekForecast: Codable {
    var median: Double
    var low: Double
    var high: Double
    var chanceOver100: Double
    var hitAt: String?
    var path: [ForecastPoint]
    var days: [ForecastDay]
    var typicalDay: Double?
    var todayPace: Double?
    var sampleDays: Int?
    var weekdayFactors: [Double]?
    var hitDate: Date? { Fmt.date(hitAt) }
}

/// Okno 5h: tempo z ostatniej godziny i przewidywany moment wyczerpania limitu.
struct FiveHourForecast: Codable {
    var ratePerHour: Double
    var projected: Double
    var hitAt: String?
    var hoursLeft: Double?
    var hitDate: Date? { Fmt.date(hitAt) }
}

struct BurnRates: Codable {
    var h1: Double?
    var h6: Double?
    var h24: Double?
    var fiveHourPerHour: Double?
}

struct PastWeek: Codable, Identifiable {
    var start: String
    var end: String
    var pct: Double
    var estimated: Bool
    var daysKnown: Int
    var id: String { start }
}

struct Stats: Codable {
    var burn: BurnRates?
    var weeks: [PastWeek]?
    var weekAvgPerDay: Double?
    var projectedWeekly: Double?
    var linearWeekly: Double?
    var forecast: WeekForecast?
    var fiveHourForecast: FiveHourForecast?
    var avgDaily30: Double?
    var daysCounted: Int?
    var daily: [DailyUse]?
    var daily30: [DailyUse]?
    var fiveHour: FiveHourStats?
    var fiveHourWindows: [FiveHourWindow]?
    var sources: [SourceShare]?
}

struct FiveHourWindow: Codable, Identifiable {
    var end: String
    var peak: Double
    var id: String { end }
    var endDate: Date? { Fmt.date(end) }
}

struct Usage: Codable {
    var updatedAt: String
    var status: String          // ok | login | error
    var plan: String?
    var message: String?
    var staleSince: String?
    var liveAt: String? = nil
    var windows: [LimitWindow]
    var stats: Stats? = nil

    /// Prawdziwy problem (logowanie, błąd) — w odróżnieniu od chwilowej przerwy po 429.
    var isProblem: Bool { status == "login" || status == "error" }
    var isThrottled: Bool { status == "throttled" }
    /// Kiedy pobrano wyświetlane procenty (przy przerwie — ostatni udany odczyt).
    var dataDate: Date? { isEstimated ? (Fmt.date(liveAt) ?? .now) : Fmt.date(staleSince ?? updatedAt) }
    /// Choć jeden limit jest szacunkiem z lokalnych logów (serwer chwilowo nie odpowiada).
    var isEstimated: Bool { windows.contains { $0.isEstimate } }
    /// Kiedy był ostatni prawdziwy odczyt z serwera.
    var serverDate: Date? { windows.compactMap(\.serverDate).first ?? Fmt.date(staleSince ?? updatedAt) }

    var fiveHour: LimitWindow? { windows.first { $0.key == "five_hour" } }
    var weekly: LimitWindow? { windows.first { $0.key == "seven_day" } }

    static let placeholder = Usage(
        updatedAt: ISO8601DateFormatter().string(from: Date()), status: "ok", plan: "pro",
        message: nil, staleSince: nil,
        windows: [
            LimitWindow(key: "five_hour", label: "Okno 5h", percent: 57,
                        resetsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800))),
            LimitWindow(key: "seven_day", label: "Tydzień", percent: 17,
                        resetsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 86400 + 6 * 3600))),
        ])
}

enum UsageStore {
    /// Prawdziwy katalog domowy (w piaskownicy widgetu NSHomeDirectory() wskazuje na kontener).
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    static var fileURL: URL {
        URL(fileURLWithPath: realHome).appendingPathComponent(".claude-usage-widget/usage.json")
    }

    static func load() -> Usage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Usage.self, from: data)
    }
}

enum Fmt {
    // Parsery tworzone raz (utworzenie ISO8601DateFormatter jest kosztowne); są bezpieczne wątkowo.
    nonisolated(unsafe) private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return isoFrac.date(from: iso) ?? isoPlain.date(from: iso)
    }

    static func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    /// „31–70%”
    static func range(_ lo: Double, _ hi: Double) -> String { "\(Int(lo.rounded()))–\(Int(hi.rounded()))%" }

    /// Szansa jako tekst: „<1%”, „12%”, „>99%”.
    static func chance(_ p: Double) -> String {
        p < 0.01 ? "<1%" : p > 0.99 ? ">99%" : "\(Int((p * 100).rounded()))%"
    }

    /// „15,0%”
    static func pct1(_ v: Double) -> String { String(format: "%.1f%%", v).replacingOccurrences(of: ".", with: ",") }

    /// Dokładny czas do resetu: „4 h 56 min”, „5 d 4 h 37 min”, „12 min”.
    static func countdown(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) d \(h) h \(m) min" }
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }

    /// Kiedy reset: „23:20” dziś, „jutro 01:00”, albo „czw. 00:00”.
    static func resetAt(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: t) { return "jutro \(time)" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pl_PL")))
        return "\(day) \(time)"
    }

    /// „reset za 4 h 56 min (23:20)”
    static func resetIn(_ date: Date?, now: Date = .now) -> String {
        guard date != nil else { return "" }
        return "reset za \(countdown(date, now: now)) (\(resetAt(date, now: now)))"
    }

    static func planName(_ p: String?) -> String {
        guard let p, !p.isEmpty else { return "" }
        return p.prefix(1).uppercased() + p.dropFirst()
    }

    static func color(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.30, green: 0.69, blue: 0.47)
        case ..<80: return Color(red: 0.85, green: 0.47, blue: 0.34)
        default: return Color(red: 0.86, green: 0.27, blue: 0.27)
        }
    }
}
