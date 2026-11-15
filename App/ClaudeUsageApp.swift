import SwiftUI

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(AppInfo.name, id: "raport") {
            RootView()
                .frame(minWidth: 1040, minHeight: 720)
                // półprzezroczyste okno — prześwituje pulpit
                .containerBackground(.ultraThinMaterial, for: .window)
                // istniejące okno obsługuje kliknięcie z widgetu (bez tworzenia kolejnych okien);
                // gdy okna nie ma, SwiftUI otworzy nowe
                .handlesExternalEvents(preferring: ["claudeusage"], allowing: ["*"])
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps: true) }
        }
        .handlesExternalEvents(matching: ["claudeusage"])
        .defaultSize(width: 1180, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

/// Zamknięcie okna raportu kończy aplikację (znika z Docka); dane i tak zbiera zadanie w tle,
/// a kliknięcie widgetu uruchomi ją ponownie.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillFinishLaunching(_ notification: Notification) { AppearanceMode.stored.apply() }
}

enum ReportTab: String, CaseIterable, Identifiable {
    case overview, week, fiveHour, history, sources, projects, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Przegląd"
        case .week: "Tydzień"
        case .fiveHour: "Okna 5h"
        case .history: "Historia"
        case .sources: "Źródła i modele"
        case .projects: "Projekty i sesje"
        case .about: "O aplikacji"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .week: "calendar"
        case .fiveHour: "clock.fill"
        case .history: "chart.bar.xaxis"
        case .sources: "chart.pie.fill"
        case .projects: "folder.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview: Palette.claude
        case .week: Palette.blue
        case .fiveHour: Palette.violet
        case .history: Palette.teal
        case .sources: Palette.amber
        case .projects: Palette.pink
        case .about: Palette.slate
        }
    }
}

struct RootView: View {
    @StateObject private var model = ReportModel()
    @AppStorage("lastTab") private var tab: ReportTab = .overview
    @State private var refreshTick = 0

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                // jeden kontener dla wszystkich szklanych kart — szkło liczone w jednym przebiegu
                GlassEffectContainer(spacing: 0) {
                    TabContent(tab: tab, model: model)
                }
                    .padding(28)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.98)).combined(with: .offset(y: -10))))
            }
            .animation(.smooth(duration: 0.3), value: tab)
            .background(AmbientBackground())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refreshTick += 1
                        model.fetchNow()
                    } label: {
                        Label {
                            Text("Odśwież")
                        } icon: {
                            Image(systemName: "arrow.clockwise").symbolEffect(.rotate, value: refreshTick)
                        }
                    }
                    .help("Pobierz świeże dane z serwera")
                }
            }
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(AppInfo.name).font(.system(size: 14, weight: .bold))
                    Text("plan \(Fmt.planName(model.usage?.plan))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)

            List(selection: $tab) {
                Section("Raport") {
                    ForEach([ReportTab.overview, .week, .fiveHour, .history, .sources, .projects]) { row($0) }
                }
                Section("Informacje") { row(.about) }
            }
            .listStyle(.sidebar)

            VStack(spacing: 10) {
                AppearancePicker()
                statusFooter
            }
            .padding(14)
        }
    }

    func row(_ t: ReportTab) -> some View {
        Label {
            Text(t.title).font(.system(size: 13.5))
        } icon: {
            GlossyIcon(symbol: t.icon, tint: t.tint, size: 22, radius: 6)
                .symbolEffect(.bounce, value: tab == t)
        }
        .tag(t)
        .padding(.vertical, 2)
    }

    var statusFooter: some View {
        let u = model.usage
        let ok = !(u?.isProblem ?? true)
        let est = u?.isEstimated == true
        let color: Color = !ok ? Palette.amber : (est ? Palette.teal : (u?.isThrottled == true ? Palette.blue : Palette.mint))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color, radius: 3)

                Text(!ok ? "Problem z danymi" : (est ? "Na żywo · szacunek" : (u?.isThrottled == true ? "Krótka przerwa" : "Na żywo")))
                    .font(.system(size: 12, weight: .semibold))
            }
            if est, let u {
                Text(estimateNote(u))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let d = u?.dataDate {
                Text("Ostatni odczyt: \(d.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let m = u?.message, u?.status != "ok", !est {
                Text(m).font(.system(size: 11)).foregroundStyle(ok ? .secondary : Palette.amber).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.smooth, value: color)
        .help("Między odczytami z serwera (który bywa odpytywany rzadziej) aplikacja dolicza zużycie z lokalnych logów Claude Code. Czaty z aplikacji Claude nie są w tych logach — kolejny odczyt serwera wszystko wyrównuje.")
    }

    func estimateNote(_ u: Usage) -> String {
        let t = u.serverDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
        let parts = u.windows.filter(\.isEstimate).compactMap { w -> String? in
            guard let s = w.serverPercent else { return nil }
            let name = w.key == "five_hour" ? "5h" : (w.key == "seven_day" ? "tydz." : w.label)
            return "\(name) \(Fmt.percent(s)) → \(w.shown)"
        }
        return "Serwer o \(t): " + parts.joined(separator: ", ") + " (doliczone z logów Claude Code)"
    }
}

struct TabContent: View {
    let tab: ReportTab
    @ObservedObject var model: ReportModel

    var body: some View {
        if model.usage?.windows.isEmpty ?? true, tab != .about {
            VStack(spacing: 12) {
                ClaudeBurst(color: Palette.claude).frame(width: 56, height: 56)
                Text("Brak danych").font(.title.bold())
                Text(model.usage?.message ?? "Uruchom install.sh, żeby pobierać limity.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 500)
        } else {
            switch tab {
            case .overview: OverviewTab(model: model)
            case .week: WeekTab(model: model)
            case .fiveHour: FiveHourTab(model: model)
            case .history: HistoryTab(model: model)
            case .sources: SourcesTab(model: model)
            case .projects: ProjectsTab(model: model)
            case .about: AboutTab(model: model)
            }
        }
    }
}
