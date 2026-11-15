import AppKit
import SwiftUI

enum AppInfo {
    static let name = "Limity Claude"
    static let author = "Tomasz Marchewka"
    static let created = "listopad 2026"
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct AboutTab: View {
    @ObservedObject var model: ReportModel

    var body: some View {
        PageStack {
            hero
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Jak to działa", icon: "gearshape.2.fill", tint: Palette.blue) {
                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Pobieranie", "Co minutę zadanie w tle pyta serwer Anthropic o procent wykorzystania limitów — to samo, co pokazuje /usage w Claude Code. Nie zużywa to tokenów.", Palette.blue)
                        step(2, "Historia", "Każdy odczyt trafia do lokalnej historii. Z niej powstają statystyki, prognozy i wykresy.", Palette.teal)
                        step(3, "Widget i raport", "Widget na pulpicie pokazuje najważniejsze liczby, a kliknięcie otwiera ten raport.", Palette.claude)
                    }
                }
                Card(title: "Prywatność", icon: "lock.shield.fill", tint: Palette.mint) {
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Wszystkie dane zostają na tym Macu.")
                        bullet("Jedyne połączenie: api.anthropic.com, tylko po procenty limitów.")
                        bullet("Token logowania zostaje w pęku kluczy macOS; aplikacja go nie wysyła nigdzie indziej.")
                        bullet("Brak analityki, reklam i zewnętrznych serwerów.")
                    }
                }
            }
            Card(title: "Twoje dane", icon: "folder.fill", tint: Palette.amber) {
                VStack(alignment: .leading, spacing: 10) {
                    pathRow("Bieżące dane", "usage.json")
                    pathRow("Historia odczytów", "history.jsonl")
                    pathRow("Szacunek dni sprzed historii", "backfill.json")
                    pathRow("Analiza lokalnych logów", "analytics.json")
                    HStack(spacing: 10) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([ReportModel.dataDirectory.appendingPathComponent("usage.json")])
                        } label: { Label("Pokaż w Finderze", systemImage: "folder") }
                        Button {
                            model.fetchNow()
                        } label: { Label("Pobierz dane teraz", systemImage: "arrow.down.circle") }
                    }
                    .padding(.top, 4)
                }
            }
            Card(title: "Metodologia", icon: "function", tint: Palette.indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Prognoza tygodnia", "4000 symulacji pozostałych dni: losowanie dziennego zużycia z ostatnich 28 dni (nowsze ważniejsze), korekta o profil dnia tygodnia i rozkład godzinowy. Wynik: mediana, zakres 10–90% i szansa przekroczenia 100%.", Palette.indigo)
                    step(2, "Okna 5h", "Tempo z ostatniej godziny odczytów serwera. Historyczne okna odtwarzane z lokalnych logów i skalibrowane do bieżącego okna serwera.", Palette.violet)
                    step(3, "Analiza logów", "Co 5 minut kolektor czyta lokalne logi Claude Code (~/.claude/projects) z 30 dni: tokeny, modele, projekty, sesje, narzędzia. Zużycie każdej odpowiedzi ważone jest rodzajem tokenów (wejście, wyjście, cache).", Palette.teal)
                    step(4, "Kalibracja", "Lokalne zużycie z bieżącego tygodnia porównywane jest z % limitu z serwera (tylko część przypadającą na Claude Code). Tak powstaje przelicznik, dzięki któremu projekty, sesje i modele pokazane są jako % limitu tygodniowego.", Palette.claude)
                    if let g = model.analytics?.generated {
                        Text("Ostatnia analiza logów: \(g.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            }
            Card(title: "Zastrzeżenie", icon: "info.circle.fill", tint: Palette.slate) {
                Text("Limity Claude to niezależny, prywatny projekt — nie jest produktem Anthropic ani nie jest przez Anthropic wspierany. Korzysta z nieoficjalnego punktu dostępowego, który może się zmienić bez zapowiedzi. Serwer podaje procenty w liczbach całkowitych; dni sprzed rozpoczęcia zapisu historii są szacowane z lokalnych logów Claude Code.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var hero: some View {
        HStack(spacing: 22) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                .tilt3D(26, maxAngle: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(AppInfo.name).font(.system(size: 34, weight: .bold))
                Text("Wersja \(AppInfo.version)").font(.system(size: 14)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: "Autor: \(AppInfo.author)", color: Palette.claude, icon: "person.fill")
                    Pill(text: AppInfo.created, color: Palette.blue, icon: "calendar")
                    Pill(text: "zbudowane z Claude Code", color: Palette.violet, icon: "sparkle")
                }
                .padding(.top, 4)
                Text("Widget i raport pokazujący na żywo wykorzystanie limitów planu Claude: okna 5-godzinnego i limitu tygodniowego.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .glassSurface(22, tint: Palette.claude)
    }

    func step(_ n: Int, _ title: String, _ text: String, _ c: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(c.gradient)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                    .shadow(color: c.opacity(0.45), radius: 4, y: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint).font(.system(size: 12))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    func pathRow(_ label: String, _ file: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).frame(width: 210, alignment: .leading)
            Text("~/.claude-usage-widget/\(file)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
