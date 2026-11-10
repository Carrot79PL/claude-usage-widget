# Limity Claude — widget i raport zużycia dla macOS

Widget na pulpit macOS i aplikacja raportowa, które pokazują, ile limitu planu Claude (Pro/Max) już wykorzystałeś: **okno 5-godzinne** i **limit tygodniowy**, w procentach, z prognozą i analizą.

## Funkcje
- **Widget** (mały / średni / duży): procent okna 5h i tygodnia, czas do resetu.
- **Aplikacja „Limity Claude”** (Liquid Glass, tryb jasny/ciemny):
  - **Przegląd**: pierścienie, prognoza tygodnia z zakresem i szansą przekroczenia limitu, budżet na dzień.
  - **Tydzień**: wykres z odczytami z serwera, przerwami, okresami dużego zużycia i prognozą.
  - **Okna 5h, Historia, Źródła i modele, Projekty i sesje**: analiza lokalnych logów Claude Code (modele, projekty, narzędzia, cache, mapa aktywności), wszystko jako % limitu.
- **Szacunek na żywo**: gdy serwer chwilowo nie odpowiada, aplikacja dolicza zużycie z logów Claude Code i oznacza wartość znakiem „≈”.

## Jak to działa
- `collector/claude_usage.py` co minutę (LaunchAgent) pobiera procenty z nieoficjalnego endpointu `api.anthropic.com/api/oauth/usage`, tego samego, którego używa `/usage` w Claude Code. Używa tokenu logowania Claude Code CLI z pęku kluczy macOS (pozycja „Claude Code-credentials”) i w razie potrzeby go odświeża.
- Wyniki trafiają do `~/.claude-usage-widget/` (`usage.json`, `history.jsonl`, `analytics.json`). Czyta je widget i aplikacja.
- Prognoza: symulacja bootstrap (4000 przebiegów) na podstawie Twojego dziennego i godzinowego profilu użycia.

## Wymagania
- macOS 26 lub nowszy, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Python 3 (python.org).
- Zalogowany Claude Code CLI (`claude`).

## Instalacja
```bash
./install.sh
```
Albo ręcznie:
```bash
xcodegen generate
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release -derivedDataPath build/dd build
```

## Uwagi
- To nieoficjalne narzędzie, niezwiązane z Anthropic. Endpoint może się zmienić bez ostrzeżenia.
- Dane nigdzie nie są wysyłane. Wszystko zostaje na Twoim komputerze, poza zapytaniem o limity do serwera Anthropic.
