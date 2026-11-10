import Foundation

// Dane z ~/.claude-usage-widget/analytics.json — analiza lokalnych logów Claude Code (30 dni),
// liczona przez kolektor co 5 minut.

struct Counters: Codable {
    var responses: Int
    var inp: Int
    var out: Int
    var cr: Int
    var cw: Int
    var think: Int
    var cost: Double
    var tools: Int
    var web: Int
    var sessions: Int?
    var projects: Int?

    enum CodingKeys: String, CodingKey {
        case responses, inp = "in", out, cr, cw, think, cost, tools, web, sessions, projects
    }

    /// Cały kontekst wysłany do modelu (świeży + z cache + zapis do cache).
    var context: Int { inp + cr + cw }
    var allTokens: Int { context + out }
}

struct DailyCounters: Codable, Identifiable {
    var date: String
    var responses: Int
    var inp: Int
    var out: Int
    var cr: Int
    var cw: Int
    var think: Int
    var cost: Double
    var tools: Int
    var sessions: Int
    var models: [String: Double]
    var id: String { date }
    var day: Date? { DateFormatter.isoDay.date(from: date) }

    enum CodingKeys: String, CodingKey {
        case date, responses, inp = "in", out, cr, cw, think, cost, tools, sessions, models
    }
}

struct ModelUse: Codable, Identifiable {
    var model: String
    var family: String
    var responses: Int
    var inp: Int
    var out: Int
    var cr: Int
    var cw: Int
    var think: Int
    var cost: Double
    var share: Double
    var avgOut: Int
    var cacheHit: Double
    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model, family, responses, inp = "in", out, cr, cw, think, cost, share, avgOut, cacheHit
    }
}

struct ProjectUse: Codable, Identifiable {
    var name: String
    var path: String?
    var responses: Int
    var out: Int
    var cost: Double
    var share: Double
    var sessions: Int
    var last: String
    var topModel: String?
    var tools: Int
    var id: String { name }
    var lastDate: Date? { Fmt.date(last) }
}

struct SessionUse: Codable, Identifiable {
    var id: String
    var project: String
    var start: String
    var end: String
    var cost: Double
    var responses: Int
    var activeMin: Int
    var entry: String?
    var topModel: String?
    var startDate: Date? { Fmt.date(start) }
}

struct SessionsSummary: Codable {
    var count: Int
    var medianActiveMin: Double
    var p90ActiveMin: Double
    var medianResponses: Double
    var totalActiveHours: Double
    var top: [SessionUse]
}

struct NamedCount: Codable, Identifiable {
    var name: String
    var count: Int
    var id: String { name }
}

struct GroupUse: Codable, Identifiable {
    var name: String
    var cost: Double
    var responses: Int
    var share: Double
    var id: String { name }
}

struct CacheStats: Codable {
    var hitRate: Double
    var savedUSD: Double
    var writeUSD: Double
    var contextPerResponse: Int
}

struct Calibration: Codable {
    var pctPerUSD: Double
    var weekValueUSD: Double
    var weekCostUSD: Double
    var claudeCodePct: Double
}

struct LogWindow: Codable, Identifiable {
    var start: String
    var end: String
    var cost: Double
    var responses: Int
    var activeMin: Int
    var estPct: Double?
    var id: String { start }
    var startDate: Date? { Fmt.date(start) }
}

struct Insight: Codable, Identifiable {
    var icon: String
    var tone: String
    var text: String
    var id: String { text }
}

struct TimelinePoint: Codable {
    var t: String
    var v: Double
    var est: Bool
    var date: Date? { Fmt.date(t) }
}

struct TimelineSpan: Codable, Identifiable {
    var start: String
    var end: String
    var hours: Double?
    var gain: Double?
    var perHour: Double?
    var est: Bool?
    var ongoing: Bool?
    var id: String { start }
    var startDate: Date? { Fmt.date(start) }
    var endDate: Date? { Fmt.date(end) }
}

struct TimelineDay: Codable, Identifiable {
    var date: String
    var gain: Double
    var est: Bool
    var activeHours: Double
    var partial: Bool
    var id: String { date }
    var day: Date? { DateFormatter.isoDay.date(from: date) }
}

/// Oś czasu bieżącego tygodnia limitu (krok 15 min) z przerwami i okresami dużego zużycia.
struct WeekTimeline: Codable {
    var start: String?
    var reset: String?
    var estimatedUntil: String?
    var points: [TimelinePoint]?
    var idle: [TimelineSpan]?
    var intense: [TimelineSpan]?
    var days: [TimelineDay]?
    var peakHour: TimelineSpan?
    var activeHours: Double?
}

struct Analytics: Codable {
    var generatedAt: String
    var totals: [String: Counters]
    var daily: [DailyCounters]
    var heatmap: [[Double]]
    var heatmapResponses: [[Int]]
    var models: [ModelUse]
    var projects: [ProjectUse]
    var projectCount: Int
    var sessions: SessionsSummary
    var tools: [NamedCount]
    var toolTotal: Int
    var entrypoints: [GroupUse]
    var efforts: [GroupUse]
    var sidechain: [GroupUse]
    var stopReasons: [String: Int]
    var cache: CacheStats
    var calibration: Calibration?
    var fiveHourWindows: [LogWindow]
    var fiveHourFactor: Double?
    var fiveHourStarts: [Int]
    var insights: [Insight]
    var weekTimeline: WeekTimeline?

    var d30: Counters? { totals["d30"] }
    var d7: Counters? { totals["d7"] }
    var prev7: Counters? { totals["prev7"] }
    var today: Counters? { totals["today"] }
    var generated: Date? { Fmt.date(generatedAt) }

    /// Przelicznik: ile % limitu tygodniowego to jednostka zużycia z logów (kalibracja z serwerem).
    var k: Double? { calibration?.pctPerUSD }
    func limitPct(_ units: Double) -> Double? { k.map { units * $0 } }
    /// „4,9%” / „86%” limitu tygodniowego albo „—”, gdy brak kalibracji.
    func limit(_ units: Double) -> String { limitPct(units).map(Fmt.limit) ?? "—" }

    static func load(from dir: URL) -> Analytics? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("analytics.json")) else { return nil }
        return try? JSONDecoder().decode(Analytics.self, from: data)
    }
}

extension Fmt {
    /// „1,3 mld”, „5,5 mln”, „12 tys.”
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        func one(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
        if d >= 1e9 { return one(d / 1e9) + " mld" }
        if d >= 1e6 { return one(d / 1e6) + " mln" }
        if d >= 1e4 { return "\(Int((d / 1e3).rounded())) tys." }
        return "\(n)"
    }

    /// „$468”, „$3,19”
    static func usd(_ v: Double) -> String {
        if v >= 100 { return "$\(Int(v.rounded()))" }
        return "$" + String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// „2 h 14 min” / „45 min”
    static func minutes(_ m: Double) -> String {
        let t = Int(m.rounded())
        return t >= 60 ? "\(t / 60) h \(t % 60) min" : "\(t) min"
    }

    static func share(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// Procent limitu: jedno miejsce po przecinku poniżej 10%.
    static func limit(_ p: Double) -> String { p < 10 ? pct1(p) : "\(Int(p.rounded()))%" }
}
