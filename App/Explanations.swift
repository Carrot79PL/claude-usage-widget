import SwiftUI

/// Opisy kart, metryk i kafelków — pokazywane po kliknięciu ⓘ albo po najechaniu kursorem.
enum Explain {
    static let card: [String: String] = [
        "Przebieg tygodnia": "Ile procent limitu tygodniowego zużyłeś od ostatniego resetu, krok po kroku. Linia ciągła to prawdziwe odczyty z serwera Anthropic. Linia przerywana na początku to szacunek z lokalnych logów Claude Code — dotyczy tylko czasu, zanim aplikacja zaczęła zbierać odczyty, i zawsze kończy się dokładnie na pierwszym prawdziwym odczycie. Wykres nigdy nie spada, bo limit w obrębie tygodnia tylko rośnie.\n\nSzare pasy to przerwy (co najmniej 3 h bez żadnej aktywności), czerwone — okresy dużego zużycia (≥ 2% limitu na godzinę). Ukośna linia pokazuje równe tempo, przy którym limit kończy się dokładnie w chwili resetu. Fioletowy pas po prawej to prognoza z zakresem 10–90%. Najedź kursorem na wykres, aby zobaczyć szczegóły dowolnego momentu.",
        "Ten tydzień": "To samo co „Przebieg tygodnia” w zakładce Tydzień: zużycie limitu od resetu, przerwy, okresy dużego zużycia i prognoza do końca tygodnia. Najedź kursorem, aby zobaczyć szczegóły.",
        "Prognoza na koniec tygodnia": "Ile procent limitu prawdopodobnie zużyjesz do resetu. Aplikacja wykonuje 4000 symulacji pozostałych dni, losując dzienne zużycie z Twoich ostatnich 28 dni (nowsze dni mają większą wagę), z uwzględnieniem tego, że w różne dni tygodnia i o różnych porach pracujesz z różną intensywnością.\n\n„Najbardziej prawdopodobnie” to mediana symulacji. „Ostrożnie” i „intensywnie” to 10. i 90. percentyl — w 8 na 10 scenariuszy wynik mieści się między nimi. Szansa przekroczenia to odsetek symulacji, w których zużycie przekroczyło 100%.",
        "Tempo zużycia": "Jak szybko teraz rośnie zużycie limitu tygodniowego, przeliczone na dobę — z prawdziwych odczytów serwera w ostatniej godzinie, 6 i 24 godzinach. Pozwala porównać bieżącą pracę z bezpiecznym tempem, przy którym limit wystarczy do resetu.",
        "Profil dni tygodnia": "Jak intensywnie pracujesz w poszczególne dni tygodnia w porównaniu z przeciętnym dniem (1,0×). Np. 1,4× oznacza dzień o 40% bardziej intensywny niż przeciętny. Liczone z ostatnich 4 tygodni i używane w prognozie.",
        "Porównanie tygodni": "Ile procent limitu zużyłeś w poprzednich okresach limitu (od resetu do resetu) w porównaniu z bieżącym tygodniem. „szac.” oznacza, że wartość pochodzi z lokalnych logów Claude Code, a nie z odczytów serwera, więc jest przybliżona.",
        "Dzień po dniu": "Ile procent limitu tygodniowego zużyłeś w każdym dniu bieżącego okresu limitu. Jaśniejsze słupki to szacunek z lokalnych logów (dni sprzed rozpoczęcia odczytów).",
        "Teraz": "Bieżące okno 5-godzinne: ile procent już zużyto i kiedy okno się odnowi. Pod spodem — czy przy tempie z ostatniej godziny limit wystarczy do końca okna.",
        "Bieżące okno": "Jak rosło wykorzystanie bieżącego okna 5h od jego początku, z odczytów serwera.",
        "Historia okien": "Najwyższe wykorzystanie (szczyt) w każdym zakończonym oknie 5h, z odczytów serwera zebranych przez aplikację.",
        "Analiza okien 5h": "Okna 5h z ostatnich 30 dni odtworzone z lokalnych logów Claude Code: okno zaczyna się z pierwszą wiadomością i trwa 5 godzin. Procenty są szacowane przez porównanie zużycia w bieżącym oknie z tym, co pokazuje serwer.",
        "Kiedy zaczynasz okna": "O której godzinie najczęściej rozpoczynają się Twoje okna 5h. Pomaga zaplanować pracę tak, by reset okna wypadał w dogodnym momencie.",
        "Dzienne zużycie": "Ile procent limitu tygodniowego zużyłeś każdego dnia w ostatnich 30 dniach. Jaśniejsze słupki to szacunek z lokalnych logów (dni sprzed rozpoczęcia odczytów).",
        "Rytm tygodnia": "Średnie dzienne zużycie w każdy dzień tygodnia z ostatnich 30 dni.",
        "Statystyki rozkładu": "Statystyki dziennego zużycia z pełnych dni: typowy dzień (mediana), intensywny dzień (90. percentyl), zmienność, trend i regularność pracy.",
        "Mapa aktywności": "Kiedy w tygodniu pracujesz z Claude Code: wiersze to dni tygodnia, kolumny to godziny. Im ciemniejszy kolor, tym większe zużycie limitu w tej godzinie (suma z 30 dni). Najedź na kratkę, aby zobaczyć szczegóły.",
        "Zużycie wg modelu dzień po dniu": "Zużycie limitu tygodniowego w każdym dniu, z podziałem na modele Claude. Linia to średnia z 7 dni, która wygładza pojedyncze intensywne dni.",
        "Podział w tym tygodniu": "Jak serwer Anthropic dzieli zużycie limitu tygodniowego między aplikacje: Claude Code, czaty, Cowork i inne.",
        "Co oznaczają źródła": "Objaśnienie nazw źródeł zużycia podawanych przez serwer.",
        "Modele": "Z jakich modeli Claude korzystał Claude Code w ostatnich 30 dniach: liczba odpowiedzi, liczba wygenerowanych tokenów, średnia długość odpowiedzi, udział kontekstu z cache i zużycie limitu tygodniowego.",
        "Struktura tokenów": "Z czego składają się tokeny przetwarzane przez Claude. Odczyt z cache to kontekst rozmowy (pliki, historia) użyty ponownie — jest go najwięcej, ale jest najtańszy. Wygenerowane to tokeny odpowiedzi; myślenie to ich część poświęcona na rozumowanie przed odpowiedzią. Paski mają skalę logarytmiczną, żeby małe wartości były widoczne.",
        "Sposób pracy": "Skąd pochodziło zużycie: z której aplikacji (terminal, aplikacja desktop, edytor), z jakim poziomem wysiłku modelu i czy pracowała główna rozmowa, czy podagenci.",
        "Projekty": "Ranking folderów (projektów), w których pracował Claude Code, według zużycia limitu tygodniowego w ostatnich 30 dniach.",
        "Sesje": "Statystyki rozmów z Claude Code. Aktywny czas to suma okresów pracy z przerwami krótszymi niż 15 minut — dłuższe przerwy nie są liczone.",
        "Narzędzia": "Których narzędzi Claude używał najczęściej (polecenia terminala, czytanie i edycja plików, integracje MCP). Pod spodem — jak kończyły się odpowiedzi: na wywołaniu narzędzia, normalnie, czy ucięte na limicie długości.",
        "Wnioski": "Automatyczne obserwacje z ostatnich 30 dni: kiedy i jak intensywnie pracujesz, co zużywa najwięcej limitu i jak zmienia się zużycie.",
        "30 dni w liczbach": "Podsumowanie pracy z Claude Code na tym Macu w ostatnich 30 dniach. Zużycie limitu jest przeliczone z lokalnych logów przez porównanie z odczytami serwera w bieżącym tygodniu.",
    ]

    static let metric: [String: String] = [
        "Ostatnia godzina": "Przyrost zużycia limitu tygodniowego w ostatniej godzinie, przeliczony na dobę (×24). Pokazuje bieżące tempo pracy.",
        "Ostatnie 6 h": "Przyrost w ostatnich 6 godzinach przeliczony na dobę. Stabilniejszy niż wartość z ostatniej godziny.",
        "Ostatnie 24 h": "Rzeczywisty przyrost zużycia w ostatniej dobie. Pojawi się, gdy historia odczytów obejmie pełną dobę.",
        "Średnio w tym tygodniu": "Średnie dzienne zużycie od ostatniego resetu limitu.",
        "Bezpieczne tempo": "Ile procent limitu możesz zużywać dziennie do resetu, aby nie przekroczyć 100%.",
        "Zapas przy obecnym tempie": "Na ile dni wystarczyłby pozostały limit, gdyby tempo z ostatnich 6 godzin trwało bez przerwy — także w nocy. To pesymistyczny scenariusz, bo zwykle robisz przerwy.",
        "Do resetu": "Ile czasu zostało do odnowienia limitu tygodniowego.",
        "Prosta proporcja": "Prognoza „naiwna”: dotychczasowe zużycie podzielone przez czas od resetu i pomnożone przez 7 dni. Dla porównania z dokładniejszą prognozą.",
        "Tokeny łącznie": "Wszystkie tokeny przetworzone przez Claude Code: kontekst wysłany do modelu (z cache i bez) oraz wygenerowane odpowiedzi.",
        "Zużycie limitu tygodnia": "Ile limitów tygodniowych zużyłeś pracą w Claude Code w ostatnich 30 dniach (100% = jeden pełny tydzień limitu).",
        "Odpowiedzi modelu": "Ile razy model wygenerował odpowiedź. Jedno Twoje polecenie zwykle wywołuje wiele odpowiedzi, bo Claude po drodze używa narzędzi.",
        "Sesje": "Liczba osobnych rozmów z Claude Code.",
        "Trafienia cache": "Jaka część kontekstu wysłanego do modelu pochodziła z cache. Wysoki odsetek oznacza oszczędne zużycie limitu.",
        "Kontekst na odpowiedź": "Średnia liczba tokenów wejścia (historia rozmowy, pliki, instrukcje), które model czyta przy każdej odpowiedzi. Długie rozmowy mają duży kontekst.",
        "Myślenie": "Jaka część wygenerowanych tokenów to rozumowanie modelu przed udzieleniem odpowiedzi.",
        "1% limitu tygodnia": "Ile średnio odpowiedzi Claude Code mieści się w 1% limitu tygodniowego.",
        "Okna w 30 dni": "Liczba okien 5h, w których pracowałeś z Claude Code.",
        "Średni szczyt (szac.)": "Szacowane średnie wykorzystanie okna 5h na jego końcu.",
        "Okna ≥ 80% (szac.)": "W ilu oknach zbliżyłeś się do limitu 5h (co najmniej 80%).",
        "Aktywny czas w oknie": "Średni czas od początku okna do ostatniej odpowiedzi w nim.",
        "Tempo teraz": "Przyrost wykorzystania okna 5h na godzinę, z ostatniej godziny odczytów.",
        "Do wyczerpania": "Za ile limit 5h się skończy, jeśli utrzymasz obecne tempo. „Nie grozi” — wystarczy do resetu okna.",
        "Pełne okno 5h": "Ile procent limitu tygodniowego zużywa wykorzystanie jednego okna 5h w 100%.",
        "Pełnych okien na tydzień": "Ile maksymalnie wykorzystanych okien 5h mieści się w limicie tygodniowym.",
        "Mediana dnia": "Typowe dzienne zużycie: połowa dni ma mniej, połowa więcej.",
        "90. percentyl": "Intensywny dzień: tylko 1 na 10 dni ma większe zużycie.",
        "Odchylenie std.": "Jak bardzo dzienne zużycie różni się od średniej. Duża wartość oznacza nieregularną pracę.",
        "Trend 14 dni": "O ile średnio zmienia się dzienne zużycie z dnia na dzień w ostatnich 2 tygodniach. Plus — pracujesz coraz intensywniej.",
        "Najdłuższa seria": "Najwięcej dni z rzędu z pracą z Claude.",
        "Weekendy": "Jaka część zużycia przypada na soboty i niedziele.",
        "Dni powyżej tempa": "Liczba dni, w których zużyłeś więcej niż 1/7 limitu tygodniowego (14,3%).",
        "Dni aktywne": "Liczba dni z jakąkolwiek pracą z Claude.",
        "Liczba sesji": "Liczba osobnych rozmów z Claude Code w 30 dniach.",
        "Typowa sesja": "Mediana aktywnego czasu sesji.",
        "Długa sesja": "90. percentyl aktywnego czasu sesji — tylko 1 na 10 sesji trwa dłużej.",
        "Odpowiedzi / sesję": "Typowa liczba odpowiedzi modelu w jednej sesji.",
        "Czas pracy": "Łączny aktywny czas pracy z Claude Code w 30 dniach.",
    ]

    static let tile: [String: String] = [
        "Wykorzystano": "Ile procent limitu tygodniowego zużyłeś od ostatniego resetu (odczyt z serwera).",
        "Pozostało": "Ile procent limitu tygodniowego zostało do resetu.",
        "Średnio dziennie": "Średnie dzienne zużycie limitu tygodniowego.",
        "Prognoza": "Najbardziej prawdopodobne zużycie na koniec tygodnia (mediana 4000 symulacji) i zakres, w którym wynik mieści się w 8 na 10 scenariuszy.",
        "Prognoza tygodnia": "Najbardziej prawdopodobne zużycie na koniec tygodnia i zakres 10–90%.",
        "Budżet na dzień": "Ile procent limitu możesz zużywać dziennie do resetu, aby nie przekroczyć 100%.",
        "Okna 5h": "Średni szczyt zakończonych okien 5h i ile razy osiągnąłeś limit okna.",
        "Zakończone okna": "Ile okien 5h zakończyło się w ostatnich 30 dniach (z odczytów serwera).",
        "Średni szczyt": "Średnie wykorzystanie okna 5h na jego końcu.",
        "Najwyższy szczyt": "Rekordowe wykorzystanie okna 5h.",
        "Limit osiągnięty": "Ile okien 5h wykorzystałeś w 100%.",
        "Najintensywniejszy": "Dzień z największym zużyciem w ostatnich 30 dniach.",
        "Najspokojniejszy": "Aktywny dzień z najmniejszym zużyciem.",
        "Powyżej tempa": "Dni, w których zużyłeś więcej niż 1/7 limitu tygodniowego.",
        "Projekty": "Liczba folderów, w których pracował Claude Code w 30 dniach.",
        "Sesje": "Liczba rozmów z Claude Code i łączny aktywny czas pracy.",
        "Wywołania narzędzi": "Ile razy Claude użył narzędzia (terminal, pliki, integracje).",
        "Dziś": "Ile procent limitu tygodniowego zużyłeś dziś w Claude Code (z lokalnych logów).",
    ]
}

/// Przycisk ⓘ z dymkiem objaśnienia.
struct InfoButton: View {
    let text: String
    var size: CGFloat = 13
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Co to znaczy?")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 360, alignment: .leading)
                .padding(16)
        }
    }
}
