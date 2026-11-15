#!/usr/bin/env python3
"""Pobiera procentowe zużycie limitów planu Claude (okno 5h, limit tygodniowy)
i zapisuje je do ~/.claude-usage-widget/usage.json dla widgetu.

Token: logowanie Claude Code CLI z pęku kluczy macOS (pozycja „Claude Code-credentials”),
czytane wyłącznie do odczytu. Gdy token wygaśnie, wystarczy uruchomić `claude` —
CLI samo go odświeży.
Uwaga: /api/oauth/usage to nieoficjalny endpoint (ten sam, którego używa /usage w Claude Code).
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

KEYCHAIN_SERVICE = "Claude Code-credentials"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URLS = ["https://platform.claude.com/v1/oauth/token", "https://console.anthropic.com/v1/oauth/token"]
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"  # publiczny client_id Claude Code (z adresu logowania)
REFRESH_MARGIN = 10 * 60  # odnów, gdy do wygaśnięcia zostało mniej niż 10 min
UA = "claude-usage-widget/1.0"
OUT_DIR = os.path.join(os.path.expanduser("~"), ".claude-usage-widget")
OUT = os.path.join(OUT_DIR, "usage.json")

LABELS = {
    "five_hour": "Okno 5h",
    "seven_day": "Tydzień",
    "seven_day_opus": "Tydzień · Opus",
    "seven_day_sonnet": "Tydzień · Sonnet",
    "seven_day_fable": "Tydzień · Fable",
}

LOGIN_MSG = "Uruchom `claude` w terminalu, żeby odświeżyć logowanie."


class AuthError(Exception):
    pass


def keychain_read():
    r = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise AuthError("Brak logowania Claude Code — uruchom `claude` i wpisz /login.")
    return json.loads(r.stdout.strip())


def keychain_account():
    r = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if '"acct"' in line and "=" in line:
            v = line.split("=", 1)[1].strip()
            if v.startswith('"') and v.endswith('"'):
                return v[1:-1]
    return os.environ.get("USER") or os.path.basename(os.path.expanduser("~"))


def keychain_write(creds):
    # Hasło idzie jako hex przez stdin `security -i`, więc nie pojawia się w liście procesów.
    hexdata = json.dumps(creds, separators=(",", ":")).encode().hex()
    acct = keychain_account().replace('"', "")
    cmd = f'add-generic-password -U -a "{acct}" -s "{KEYCHAIN_SERVICE}" -X {hexdata}\n'
    r = subprocess.run(["/usr/bin/security", "-i"], input=cmd, capture_output=True, text=True)
    if r.returncode != 0 or "error" in (r.stdout + r.stderr).lower():
        raise RuntimeError("Nie udało się zapisać odnowionego tokenu do pęku kluczy.")


def curl_json(url, headers, body=None):
    """Zapytanie przez systemowy curl; nagłówki (lub treść) idą przez stdin, nie w argumentach."""
    args = ["/usr/bin/curl", "-sS", "--max-time", "20", "-w", "\n%{http_code}\n%header{retry-after}"]
    if body is None:
        args += ["-H", "@-"]
        stdin = "".join(f"{k}: {v}\n" for k, v in headers.items())
    else:
        for k, v in headers.items():
            args += ["-H", f"{k}: {v}"]
        args += ["--data-binary", "@-"]
        stdin = json.dumps(body)
    r = subprocess.run(args + [url], input=stdin, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"curl: {r.stderr.strip()}")
    rest, _, retry_after = r.stdout.rpartition("\n")
    text, _, code = rest.rpartition("\n")
    return int(code or 0), text, retry_after.strip()


def refresh(creds):
    oauth = creds["claudeAiOauth"]
    payload = {"grant_type": "refresh_token", "refresh_token": oauth["refreshToken"], "client_id": CLIENT_ID}
    hdrs = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": UA}
    code, text = 0, ""
    for url in TOKEN_URLS:
        code, text, _ = curl_json(url, hdrs, payload)
        if code == 200:
            break
        if code in (400, 401):
            raise AuthError("Sesja wygasła — uruchom `claude` i zaloguj się ponownie (/login).")
    else:
        raise RuntimeError(f"Odnawianie tokenu: HTTP {code}")
    t = json.loads(text)
    oauth["accessToken"] = t["access_token"]
    if t.get("refresh_token"):
        oauth["refreshToken"] = t["refresh_token"]
    oauth["expiresAt"] = int((time.time() + int(t.get("expires_in", 3600))) * 1000)
    keychain_write(creds)
    return oauth["accessToken"]


def read_token(force_refresh=False):
    creds = keychain_read()
    oauth = creds.get("claudeAiOauth") or {}
    if not oauth.get("accessToken"):
        raise AuthError("Brak tokenu w danych logowania Claude Code.")
    if force_refresh or oauth.get("expiresAt", 0) / 1000 < time.time() + REFRESH_MARGIN:
        if not oauth.get("refreshToken"):
            raise AuthError("Token wygasł. " + LOGIN_MSG)
        return refresh(creds), oauth.get("subscriptionType")
    return oauth["accessToken"], oauth.get("subscriptionType")


class TokenRejected(Exception):
    pass


class Throttled(Exception):
    """Serwer odpowiedział 429 — trzeba odczekać."""
    def __init__(self, retry_after):
        super().__init__("HTTP 429")
        self.retry_after = retry_after


def fetch_usage(token):
    # Systemowy curl używa certyfikatów macOS (Python z python.org ich nie widzi).
    code, body, retry_after = curl_json(USAGE_URL, {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
        "User-Agent": UA,
    })
    if code in (401, 403):
        raise TokenRejected()
    if code == 429:
        raise Throttled(retry_after)
    if code != 200:
        raise RuntimeError(f"Serwer odpowiedział błędem HTTP {code}.")
    return json.loads(body)


STATE = os.path.join(OUT_DIR, "state.json")
MIN_INTERVAL, MAX_INTERVAL = 60, 900      # docelowo co minutę; po odrzuceniach maks. co 15 min
MIN_BACKOFF, MAX_BACKOFF = 120, 1800


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(st):
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(st, f, indent=1)


def _local_hm(dt):
    return dt.astimezone().strftime("%H:%M")


def main():
    now = datetime.now(timezone.utc)
    forced = "--now" in sys.argv or "--force-refresh" in sys.argv
    st = load_state()
    interval = int(st.get("interval", MIN_INTERVAL))
    next_at = _dt(st.get("nextFetchAt"))
    last_try = _dt(st.get("lastAttempt"))
    if not forced:
        if (next_at and now < next_at) or (last_try and (now - last_try).total_seconds() < interval - 5):
            # przerwa po 429 albo jeszcze nie pora — tylko odśwież szacunek z lokalnych logów
            refresh_live(now)
            return
    st["lastAttempt"] = now.isoformat()

    out = {"updatedAt": now.isoformat(), "status": "ok", "plan": None, "windows": []}
    try:
        token, out["plan"] = read_token(force_refresh="--force-refresh" in sys.argv)
        try:
            raw = fetch_usage(token)
        except TokenRejected:
            token, _ = read_token(force_refresh=True)
            try:
                raw = fetch_usage(token)
            except TokenRejected:
                raise AuthError("Serwer odrzucił token. " + LOGIN_MSG)
        for key, val in raw.items():
            if isinstance(val, dict) and val.get("utilization") is not None:
                out["windows"].append({
                    "key": key,
                    "label": LABELS.get(key, key.replace("_", " ")),
                    "percent": float(val["utilization"]),
                    "resetsAt": val.get("resets_at"),
                })
        order = list(LABELS)
        out["windows"].sort(key=lambda w: order.index(w["key"]) if w["key"] in order else 99)
        if not out["windows"]:
            out.update(status="error", message="Serwer nie zwrócił żadnych limitów.")
        rows = (raw.get("seven_day_breakdown") or {}).get("rows") or []
        out["sources"] = [{"name": SOURCE_NAMES.get(r.get("key"), r.get("display_name") or r.get("key")),
                           "percent": r.get("percent", 0)} for r in rows]
        # sukces: po godzinie bez odrzuceń stopniowo wracamy do odpytywania co minutę
        st.pop("nextFetchAt", None)
        st["backoff"] = 0
        streak = _dt(st.get("okSince")) or now
        if interval > MIN_INTERVAL and (now - streak).total_seconds() >= 3600:
            interval, streak = max(MIN_INTERVAL, interval // 2), now
        st["okSince"] = streak.isoformat()
    except Throttled as e:
        try:
            wait = int(e.retry_after)
        except ValueError:
            wait = int(st.get("backoff") or MIN_BACKOFF // 2) * 2
        wait = max(MIN_BACKOFF, min(MAX_BACKOFF, wait))
        st["backoff"] = wait
        st["nextFetchAt"] = (now + timedelta(seconds=wait)).isoformat()
        st.pop("okSince", None)
        interval = min(MAX_INTERVAL, max(interval * 2, 120))
        out.update(status="throttled",
                   message=f"Serwer prosi o wolniejsze odpytywanie — kolejna próba o {_local_hm(now + timedelta(seconds=wait))}.")
    except AuthError as e:
        out.update(status="login", message=str(e))
    except Exception as e:  # sieć, zmiana API itp.
        out.update(status="error", message=f"{type(e).__name__}: {e}")

    if out["status"] != "ok":
        # zostaw ostatnie dobre dane, żeby widget nie pustoszał przy chwilowym problemie
        try:
            with open(OUT) as f:
                prev = json.load(f)
            if prev.get("windows"):
                out["windows"], out["plan"] = prev["windows"], out["plan"] or prev.get("plan")
                out["staleSince"] = prev.get("staleSince") or prev.get("updatedAt")
        except (OSError, ValueError):
            pass

    if out["status"] != "ok":   # świeży odczyt serwera zawsze wygrywa — szacunek tylko przy braku odczytu
        try:
            apply_live_estimate(out, now)
        except Exception as e:
            out["liveError"] = f"{type(e).__name__}: {e}"
    st["interval"] = interval
    out["pollEverySeconds"] = interval
    save_state(st)
    os.makedirs(OUT_DIR, exist_ok=True)
    try:
        if out["status"] == "ok":
            append_history(out, now)
        out["stats"] = compute_stats(out, now)
    except Exception as e:  # statystyki nie mogą zepsuć podstawowych danych
        out["statsError"] = f"{type(e).__name__}: {e}"
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    os.replace(tmp, OUT)
    try:
        maybe_analytics(out, now)
    except Exception as e:
        with open(os.path.join(OUT_DIR, "collector.log"), "a") as f:
            f.write(f"{now.isoformat()} analytics: {type(e).__name__}: {e}\n")
    if "-v" in sys.argv:
        print(json.dumps(out, indent=1, ensure_ascii=False))


# ---------------------------------------------------------------- statystyki

HIST = os.path.join(OUT_DIR, "history.jsonl")
BACKFILL = os.path.join(OUT_DIR, "backfill.json")
HIST_DAYS = 45
WEEK = timedelta(days=7)
SOURCE_NAMES = {"claude_code": "Claude Code", "chat": "Czaty", "cowork": "Cowork", "other": "Inne"}


def _dt(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


# ---------------------------------------------------------------- szacunek na żywo

LIVE_AFTER = 90   # s — starszy odczyt serwera uzupełniamy zużyciem z logów Claude Code


def refresh_live(now):
    """Między odczytami z serwera: przelicza szacunek w usage.json (bez odpytywania)."""
    try:
        with open(OUT) as f:
            out = json.load(f)
    except (OSError, ValueError):
        return
    if not out.get("windows") or out.get("status") == "ok" and not any(w.get("estimated") for w in out["windows"]) \
            and (now - _dt(out["updatedAt"])).total_seconds() < LIVE_AFTER:
        return
    before = [(w.get("percent"), w.get("resetsAt")) for w in out["windows"]]
    try:
        apply_live_estimate(out, now)
    except Exception as e:
        out["liveError"] = f"{type(e).__name__}: {e}"
    if [(w.get("percent"), w.get("resetsAt")) for w in out["windows"]] == before:
        return
    out["liveAt"] = now.isoformat()
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    os.replace(tmp, OUT)


def apply_live_estimate(out, now):
    """Ostatni odczyt serwera + zużycie z lokalnych logów Claude Code od tamtej chwili.

    Serwer bywa odpytywany rzadziej (po 429 nawet co 15 min), a w tym czasie limit rośnie.
    Przeliczniki % / jednostkę zużycia pochodzą z kalibracji (analytics.json). Czaty z aplikacji
    Claude nie trafiają do lokalnych logów, więc szacunek może je pominąć — kolejny odczyt
    serwera wszystko wyrównuje.
    """
    for w in out.get("windows", []):
        if "serverPercent" in w:                     # cofnij poprzedni szacunek
            w["percent"] = w.pop("serverPercent")
            w["resetsAt"] = w.pop("serverResetsAt", w.get("resetsAt"))
        w.pop("estimated", None); w.pop("serverAt", None); w.pop("liveAdded", None)
    out.pop("liveAt", None)
    hist = load_history()
    if not hist:
        return
    last = hist[-1]
    t0 = _dt(last["t"])
    if (now - t0).total_seconds() < LIVE_AFTER:
        return
    try:
        with open(ANALYTICS) as f:
            a = json.load(f)
    except (OSError, ValueError):
        return
    k = (a.get("calibration") or {}).get("pctPerUSD")
    f5 = a.get("fiveHourFactor")
    recs = load_records(t0 - timedelta(hours=1))
    for r in recs:
        r["cost"] = _cost(r["model"], r["u"])

    def cost_since(t):
        return sum(r["cost"] for r in recs if r["t"] > t)

    def mark(w, value, reset=None):
        w["serverPercent"], w["serverResetsAt"], w["serverAt"] = w["percent"], w.get("resetsAt"), last["t"]
        w["liveAdded"] = round(value - (w["percent"] if reset is None else 0), 2)
        w["percent"] = round(min(100.0, value), 1)
        if reset is not None:
            w["resetsAt"] = reset.isoformat()
        w["estimated"] = True

    h, wk = _win(out, "five_hour"), _win(out, "seven_day")
    if h and f5 and last.get("h") is not None:
        hr = _dt(last.get("hr"))
        if hr and now >= hr:
            # okno się zresetowało — nowe zaczyna się od pierwszej odpowiedzi po resecie
            after = [r for r in recs if r["t"] >= hr]
            if after:
                start = after[0]["t"].replace(minute=0, second=0, microsecond=0)
                mark(h, sum(r["cost"] for r in after) * f5, start + timedelta(hours=5))
            else:
                mark(h, 0.0, hr)
                h["resetsAt"] = None
        else:
            add = cost_since(t0) * f5
            if add >= 0.05:
                h["percent"] = last["h"]
                mark(h, last["h"] + add)
    if wk and k:
        wr = _dt(last.get("wr"))
        if wr and now >= wr:
            mark(wk, cost_since(wr) * k, wr + WEEK)
        else:
            add = cost_since(t0) * k
            if add >= 0.05:
                wk["percent"] = last["w"]
                mark(wk, last["w"] + add)


def _win(out, key):
    return next((w for w in out.get("windows", []) if w["key"] == key), None)


def _local_day(dt):
    return dt.astimezone().date().isoformat()


def append_history(out, now):
    h, w = _win(out, "five_hour"), _win(out, "seven_day")
    if not w:
        return
    rec = {"t": now.isoformat(), "w": w["percent"], "wr": w["resetsAt"],
           "h": h["percent"] if h else None, "hr": h["resetsAt"] if h else None}
    with open(HIST, "a") as f:
        f.write(json.dumps(rec) + "\n")
    # raz na dobę przytnij historię do HIST_DAYS dni
    if os.path.getsize(HIST) > 0 and now.minute < 5 and now.hour == 3:
        keep = [r for r in load_history() if _dt(r["t"]) > now - timedelta(days=HIST_DAYS)]
        with open(HIST, "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in keep)


def load_history():
    rows = []
    try:
        with open(HIST) as f:
            for line in f:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return sorted(rows, key=lambda r: r["t"])


def _same_window(a, b):
    da, db = _dt(a), _dt(b)
    return da and db and abs((da - db).total_seconds()) < 600


# Szacunek dni sprzed historii: koszt z lokalnych logów Claude Code (ceny API jako wagi),
# przeliczony na % limitu tygodnia współczynnikiem dopasowanym do prawdziwego wyniku z serwera.
PRICES = {  # $ / 1M tokenów: input, output, cache read
    "claude-fable-5": (10.0, 50.0, 0.25), "claude-mythos-5": (10.0, 50.0, 0.25),
    "claude-opus-5-5": (4.0, 20.0, 0.20), "claude-opus": (5.0, 25.0, 0.50),
    "claude-sonnet-5": (2.0, 10.0, 0.20), "claude-sonnet": (3.0, 15.0, 0.30),
    "claude-haiku-5": (0.10, 0.50, 0.01), "claude-haiku": (1.0, 5.0, 0.10),
}


def _cost(model, u):
    key = max((k for k in PRICES if model.startswith(k)), key=len, default="claude-opus-5-5")
    pin, pout, pread = PRICES[key]
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens") or 0
    w5m = (cc.get("ephemeral_5m_input_tokens") or 0) or ((u.get("cache_creation_input_tokens") or 0) if not w1h else 0)
    return ((u.get("input_tokens") or 0) * pin + (u.get("output_tokens") or 0) * pout
            + (u.get("cache_read_input_tokens") or 0) * pread + w5m * pin * 1.25 + w1h * pin * 2) / 1e6


def local_costs(since, until):
    """Koszt wg dnia (lokalnie) z ~/.claude/projects/**/*.jsonl w przedziale [since, until)."""
    import glob
    recs = {}
    base = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    for path in glob.iglob(os.path.join(base, "**", "*.jsonl"), recursive=True):
        try:
            if os.path.getmtime(path) < since.timestamp():
                continue
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if '"usage"' not in line:
                        continue
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    msg = d.get("message")
                    if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict) or not d.get("timestamp"):
                        continue
                    t = _dt(d["timestamp"])
                    if since <= t < until and (msg.get("model") or "").startswith("claude"):
                        recs[(msg.get("id"), d.get("requestId"))] = (t, msg["model"], msg["usage"])
        except OSError:
            continue
    days = {}
    for t, model, u in recs.values():
        k = _local_day(t)
        days[k] = days.get(k, 0.0) + _cost(model, u)
    return days


def build_backfill(out, now, history_start):
    """Liczone raz: szacowany % limitu tygodnia na dzień dla 30 dni przed początkiem historii."""
    w = _win(out, "seven_day")
    if not w or not w.get("resetsAt") or w["percent"] < 2:
        return None
    week_start = _dt(w["resetsAt"]) - WEEK
    week_costs = local_costs(week_start, now)
    total = sum(week_costs.values())
    if total <= 0:
        return None
    k = w["percent"] / total
    since = (now - timedelta(days=31)).astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    est = {d: round(c * k, 2) for d, c in local_costs(since, history_start).items()}
    data = {"createdAt": now.isoformat(), "historyStart": history_start.isoformat(), "factor": k, "days": est}
    with open(BACKFILL, "w") as f:
        json.dump(data, f, indent=1)
    return data


def compute_stats(out, now):
    hist = load_history()
    stats = {"sources": out.get("sources") or []}
    w = _win(out, "seven_day")

    # Tempo tygodnia: liniowa prognoza do momentu resetu.
    if w and w.get("resetsAt"):
        start = _dt(w["resetsAt"]) - WEEK
        elapsed = (now - start).total_seconds() / 86400
        stats["weekElapsedDays"] = round(elapsed, 2)
        stats["weekAvgPerDay"] = round(w["percent"] / elapsed, 2) if elapsed > 0.25 else None
        stats["projectedWeekly"] = round(w["percent"] / (elapsed / 7), 1) if elapsed >= 0.5 else None

    # Dzienne zużycie limitu tygodnia z historii (przyrosty między odczytami).
    real = {}
    for a, b in zip(hist, hist[1:]):
        delta = max(0.0, b["w"] - a["w"]) if _same_window(a["wr"], b["wr"]) else b["w"]
        day = _local_day(_dt(b["t"]))
        real[day] = real.get(day, 0.0) + delta
    history_start = _dt(hist[0]["t"]) if hist else now
    if hist:
        real.setdefault(_local_day(history_start), 0.0)
        stats["historySince"] = hist[0]["t"]

    backfill = None
    try:
        with open(BACKFILL) as f:
            backfill = json.load(f)
    except (OSError, ValueError):
        backfill = build_backfill(out, now, history_start)
    # Szacunek obejmuje tylko czas sprzed pierwszego odczytu, więc dzień startu historii
    # to suma: szacunek (przed odczytem) + prawdziwe przyrosty (po nim).
    est = (backfill or {}).get("days", {})

    today = now.astimezone().date()
    series = []
    for i in range(29, -1, -1):
        d = (today - timedelta(days=i)).isoformat()
        r, e = real.get(d), est.get(d, 0.0)
        if r is None and d not in est:
            series.append({"date": d, "pct": None, "estimated": False})
            continue
        val = (r or 0.0) + e
        series.append({"date": d, "pct": round(val, 2), "estimated": (r is None) or e > (r or 0)})
    stats["daily"] = series[-14:]
    stats["daily30"] = series
    past = [s["pct"] for s in series[:-1] if s["pct"] is not None]  # bez dzisiejszego, niepełnego dnia
    stats["avgDaily30"] = round(sum(past) / len(past), 2) if past else None
    stats["daysCounted"] = len(past)

    # Okna 5h z historii: szczyt w każdym zakończonym oknie.
    peaks = {}
    for r in hist:
        if r.get("hr") is None or r.get("h") is None:
            continue
        key = _dt(r["hr"]).replace(second=0, microsecond=0).isoformat()
        peaks[key] = max(peaks.get(key, 0.0), r["h"])
    done_items = sorted((k, p) for k, p in peaks.items() if _dt(k) <= now and _dt(k) > now - timedelta(days=30))
    done = [p for _, p in done_items]
    stats["fiveHourWindows"] = [{"end": k, "peak": p} for k, p in done_items]
    stats["fiveHour"] = {"windows": len(done),
                         "avgPeak": round(sum(done) / len(done), 1) if done else None,
                         "limitHits": sum(1 for p in done if p >= 100)}

    stats["burn"] = burn_rates(hist, now)
    stats["weeks"] = past_weeks(out, series)

    try:
        fc = forecast_week(out, now, series, backfill, history_start)
        if fc:
            stats["forecast"] = fc
            stats["linearWeekly"] = stats.get("projectedWeekly")
            stats["projectedWeekly"] = fc["median"]
    except Exception as e:  # prognoza nie może zepsuć reszty
        stats["forecastError"] = str(e)
    try:
        f5 = forecast_five_hour(out, now, hist)
        if f5:
            stats["fiveHourForecast"] = f5
    except Exception as e:
        stats["forecastError"] = str(e)
    return stats


# ---------------------------------------------------------------------------
# Prognoza
#
# Tydzień: symulacja (bootstrap) pozostałego czasu do resetu. Dla każdego kolejnego
# dnia losujemy dzienne zużycie z ostatnich ~4 tygodni (nowsze dni ważniejsze),
# korygujemy je o typowy dla tego dnia tygodnia poziom i mnożymy przez część dnia,
# która jeszcze została (wg rozkładu godzinowego z lokalnych logów). Z 4000 przebiegów
# bierzemy medianę, zakres 10–90% i szansę przekroczenia 100%.

PROFILE = os.path.join(OUT_DIR, "hourly_profile.json")
SIMS = 4000


def hourly_profile(now):
    """Udział każdej godziny doby w dziennym zużyciu (liczone raz na dobę z lokalnych logów)."""
    try:
        with open(PROFILE) as f:
            data = json.load(f)
        if data.get("day") == _local_day(now):
            return data["shares"]
    except (OSError, ValueError, KeyError):
        pass
    hours = [0.0] * 24
    for r in load_records(now - timedelta(days=30)):
        hours[r["t"].astimezone().hour] += _cost(r["model"], r["u"])
    total = sum(hours)
    # wygładzenie: odrobina zużycia możliwa o każdej porze
    shares = [(h / total if total else 1 / 24) * 0.9 + 0.1 / 24 for h in hours]
    with open(PROFILE, "w") as f:
        json.dump({"day": _local_day(now), "shares": shares}, f)
    return shares


def _share_between(shares, a, b):
    """Jaka część typowego dziennego zużycia przypada na czas [a, b) (ten sam dzień lokalny)."""
    a, b = a.astimezone(), b.astimezone()
    total, t = 0.0, a
    while t < b:
        nxt = min(b, (t + timedelta(hours=1)).replace(minute=0, second=0, microsecond=0))
        total += shares[t.hour] * (nxt - t).total_seconds() / 3600
        t = nxt
    return total


def _quantile(sorted_vals, q):
    if not sorted_vals:
        return 0.0
    i = q * (len(sorted_vals) - 1)
    lo = int(i)
    hi = min(lo + 1, len(sorted_vals) - 1)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (i - lo)


def forecast_week(out, now, series, backfill, history_start):
    import random
    w = _win(out, "seven_day")
    if not w or not w.get("resetsAt"):
        return None
    reset = _dt(w["resetsAt"])
    current = float(w["percent"])
    if reset <= now:
        return None

    # Próbka dni: ostatnie 28 pełnych dni. Dni bez wpisu w okresie objętym szacunkiem/historią = 0.
    covered_from = history_start.astimezone().date()
    if backfill and backfill.get("createdAt"):
        covered_from = min(covered_from, (_dt(backfill["createdAt"]) - timedelta(days=30)).astimezone().date())
    today = now.astimezone().date()
    pool = []  # (wartość, dzień tygodnia, waga)
    for i, s_ in enumerate(reversed(series[:-1])):  # od wczoraj wstecz
        if i >= 28:
            break
        d = datetime.fromisoformat(s_["date"]).date()
        if d < covered_from:
            continue
        v = s_["pct"] if s_["pct"] is not None else 0.0
        pool.append((v, d.weekday(), 0.93 ** i))
    if len(pool) < 3:
        return None

    tw = sum(p[2] for p in pool)
    mean = sum(p[0] * p[2] for p in pool) / tw
    if mean <= 0:
        mean = 1e-6
    # Korekta dnia tygodnia, ściągnięta do 1 przy małej liczbie próbek.
    wd_factor = []
    for wd in range(7):
        vals = [p[0] for p in pool if p[1] == wd]
        k = 2.0
        m = (sum(vals) + k * mean) / (len(vals) + k)
        wd_factor.append(m / mean)

    # Dzisiejsze tempo: ile już zużyto dziś względem typowej części dnia, która minęła.
    shares = hourly_profile(now)
    local_now = now.astimezone()
    midnight = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_real = series[-1]["pct"] or 0.0
    elapsed_share = _share_between(shares, midnight, local_now)

    # Odcinki do resetu: reszta dziś, pełne dni, końcówka przed resetem.
    segs = []  # (koniec, dzień tygodnia, udział dnia)
    t = local_now
    reset_local = reset.astimezone()
    while t < reset_local:
        day_end = (t + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        end = min(day_end, reset_local)
        if (end - t).total_seconds() >= 60:
            segs.append((end, t.weekday(), _share_between(shares, t, end)))
        t = end

    rng = random.Random(1234)
    vals_w = [(p[0], p[2]) for p in pool]
    values = [v for v, _ in vals_w]
    weights = [wt for _, wt in vals_w]
    # Dzień dzisiejszy: jeśli ktoś dziś mocno pracuje, reszta dnia też będzie intensywniejsza.
    today_boost = 1.0
    if elapsed_share > 0.15:
        exp_so_far = mean * wd_factor[local_now.weekday()] * elapsed_share
        if exp_so_far > 0:
            today_boost = max(0.5, min(2.5, (today_real / exp_so_far) ** 0.5))

    cum_by_seg = [[] for _ in segs]
    finals = []
    for _ in range(SIMS):
        total = current
        draws = rng.choices(values, weights=weights, k=len(segs))
        for j, ((end, wd, share), dv) in enumerate(zip(segs, draws)):
            boost = today_boost if j == 0 else 1.0
            total += dv * wd_factor[wd] * share * boost
            cum_by_seg[j].append(total)
        finals.append(total)
    finals.sort()
    for c in cum_by_seg:
        c.sort()

    path = [{"t": now.replace(microsecond=0).isoformat(), "median": round(current, 1), "low": round(current, 1), "high": round(current, 1)}]
    days = []
    prev_med = current
    for (end, wd, share), c in zip(segs, cum_by_seg):
        med = _quantile(c, 0.5)
        path.append({"t": end.astimezone(timezone.utc).replace(microsecond=0).isoformat(), "median": round(med, 1),
                     "low": round(_quantile(c, 0.1), 1), "high": round(_quantile(c, 0.9), 1)})
        days.append({"date": (end - timedelta(seconds=1)).date().isoformat(),
                     "expected": round(med - prev_med, 1), "share": round(share, 2)})
        prev_med = med

    # Kiedy mediana przekroczy 100% (interpolacja w obrębie odcinka).
    hit_at = None
    for a, b in zip(path, path[1:]):
        if a["median"] < 100 <= b["median"]:
            ta, tb = _dt(a["t"]), _dt(b["t"])
            f = (100 - a["median"]) / max(1e-9, b["median"] - a["median"])
            hit_at = (ta + (tb - ta) * f).replace(microsecond=0).isoformat()
            break

    over = sum(1 for v in finals if v >= 100) / len(finals)
    return {
        "median": round(_quantile(finals, 0.5), 1),
        "low": round(_quantile(finals, 0.1), 1),
        "high": round(_quantile(finals, 0.9), 1),
        "chanceOver100": round(over, 3),
        "hitAt": hit_at,
        "path": path,
        "days": days,
        "typicalDay": round(mean, 2),
        "todayPace": round(today_boost, 2),
        "sampleDays": len(pool),
        "weekdayFactors": [round(x, 2) for x in wd_factor],
    }


def forecast_five_hour(out, now, hist):
    """Okno 5h: tempo z ostatniej godziny bieżącego okna → kiedy skończy się limit."""
    w = _win(out, "five_hour")
    if not w or not w.get("resetsAt"):
        return None
    reset = _dt(w["resetsAt"])
    cur = float(w["percent"])
    rows = [r for r in hist if r.get("hr") and _same_window(r["hr"], w["resetsAt"]) and r.get("h") is not None]
    hours_left = max(0.0, (reset - now).total_seconds() / 3600)
    if not rows:
        return {"ratePerHour": 0.0, "projected": cur, "hitAt": None, "hoursLeft": round(hours_left, 2)}
    recent = [r for r in rows if _dt(r["t"]) >= now - timedelta(minutes=60)] or rows
    first = recent[0]
    span = (now - _dt(first["t"])).total_seconds() / 3600
    # krótka próbka → mieszamy z tempem od początku okna
    window_start = reset - timedelta(hours=5)
    since_start = max(1 / 6, (now - window_start).total_seconds() / 3600)
    rate_all = cur / since_start
    rate_recent = (cur - first["h"]) / span if span >= 1 / 6 else rate_all
    wgt = min(1.0, span)  # pełna waga tempa z ostatniej godziny, gdy próbka ma ≥ 1 h
    rate = max(0.0, wgt * rate_recent + (1 - wgt) * rate_all)
    projected = min(100.0, cur + rate * hours_left)
    hit_at = None
    if rate > 0 and cur < 100:
        t_hit = now + timedelta(hours=(100 - cur) / rate)
        if t_hit < reset:
            hit_at = t_hit.replace(microsecond=0).isoformat()
    return {"ratePerHour": round(rate, 1), "projected": round(projected, 1), "hitAt": hit_at,
            "hoursLeft": round(hours_left, 2)}


def burn_rates(hist, now):
    """Tempo przyrostu limitu tygodnia (%/dobę) i okna 5h (%/h) w kilku horyzontach."""
    res = {}
    if not hist:
        return res
    last = hist[-1]
    for label, hours in (("h1", 1), ("h6", 6), ("h24", 24)):
        since = now - timedelta(hours=hours)
        rows = [r for r in hist if _dt(r["t"]) >= since]
        if len(rows) < 2:
            continue
        gain = 0.0
        for a, b in zip(rows, rows[1:]):
            gain += max(0.0, b["w"] - a["w"]) if _same_window(a["wr"], b["wr"]) else b["w"]
        span = (_dt(rows[-1]["t"]) - _dt(rows[0]["t"])).total_seconds() / 3600
        if span >= hours * 0.5:
            res[label] = round(gain / span * 24, 2)   # % tygodnia na dobę
    # okno 5h: przyrost w ostatniej godzinie
    rows = [r for r in hist if _dt(r["t"]) >= now - timedelta(hours=1) and r.get("hr") and _same_window(r["hr"], last.get("hr"))]
    if len(rows) >= 2:
        span = (_dt(rows[-1]["t"]) - _dt(rows[0]["t"])).total_seconds() / 3600
        if span > 0.15:
            res["fiveHourPerHour"] = round(max(0.0, rows[-1]["h"] - rows[0]["h"]) / span, 1)
    return res


def past_weeks(out, series):
    """Suma dziennego zużycia w poprzednich okresach limitu (wyrównanych do resetu)."""
    w = _win(out, "seven_day")
    if not w or not w.get("resetsAt"):
        return []
    reset_day = _dt(w["resetsAt"]).astimezone().date()
    by_day = {s_["date"]: s_ for s_ in series}
    weeks = []
    for k in range(1, 5):
        end = reset_day - timedelta(days=7 * k)
        start = end - timedelta(days=7)
        vals, est, known = 0.0, False, 0
        for i in range(7):
            d = (start + timedelta(days=i)).isoformat()
            s_ = by_day.get(d)
            if s_ and s_["pct"] is not None:
                vals += s_["pct"]; known += 1
                est = est or s_["estimated"]
        if known >= 4:
            weeks.append({"start": start.isoformat(), "end": end.isoformat(), "pct": round(vals, 1),
                          "estimated": est, "daysKnown": known})
    return weeks


# ---------------------------------------------------------------------------
# Analiza lokalnych logów Claude Code → analytics.json (co 5 min)

ANALYTICS = os.path.join(OUT_DIR, "analytics.json")
ANALYTICS_EVERY = 300
PL_WEEKDAYS = ["pon.", "wt.", "śr.", "czw.", "pt.", "sob.", "niedz."]


def _project_name(cwd):
    if not cwd:
        return "(nieznany)"
    if "/.claude/worktrees/" in cwd:
        cwd = cwd.split("/.claude/worktrees/")[0]
    return os.path.basename(cwd.rstrip("/")) or cwd


def _tool_group(name):
    if name.startswith("mcp__"):
        parts = name.split("__")
        return "MCP: " + (parts[1] if len(parts) > 1 else "?")
    return name


def _price(model):
    key = max((k for k in PRICES if model.startswith(k)), key=len, default="claude-opus-5-5")
    return PRICES[key]


RECORDS_CACHE = os.path.join(OUT_DIR, "records_cache.json")
USAGE_KEYS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens",
              "cache_creation", "output_tokens_details", "server_tool_use")


def load_records(since):
    """Odpowiedzi modelu z lokalnych logów od `since`.

    Przyrostowo: pliki .jsonl są tylko dopisywane, więc pamiętamy, do którego bajtu
    każdy został przeczytany, i przy kolejnym przebiegu czytamy wyłącznie nowe linie.
    Pełne przeczytanie (ok. 600 MB) dzieje się tylko za pierwszym razem.
    """
    import glob
    try:
        with open(RECORDS_CACHE) as f:
            cache = json.load(f)
        if cache.get("version") != 2:
            raise ValueError
    except (OSError, ValueError):
        cache = {"version": 2, "files": {}, "recs": {}}
    files, recs = cache["files"], cache["recs"]
    dirty = False
    base = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    horizon = since.timestamp() - 86400
    for path in glob.iglob(os.path.join(base, "**", "*.jsonl"), recursive=True):
        try:
            st = os.stat(path)
        except OSError:
            continue
        if st.st_mtime < horizon:
            continue
        info = files.get(path)
        offset = info["offset"] if info and info["offset"] <= st.st_size else 0
        if info and offset == st.st_size:
            continue  # bez zmian
        try:
            with open(path, "rb") as f:
                f.seek(offset)
                chunk = f.read()
        except OSError:
            continue
        cut = chunk.rfind(b"\n")
        if cut < 0:
            continue  # niedokończona linia — poczekamy
        files[path] = {"offset": offset + cut + 1}
        dirty = True
        for raw in chunk[:cut].split(b"\n"):
            if b'"assistant"' not in raw:
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message")
            if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict) or not d.get("timestamp"):
                continue
            model = msg.get("model") or ""
            if not model.startswith("claude"):
                continue
            u = msg["usage"]
            u = {k_: u[k_] for k_ in USAGE_KEYS if k_ in u}
            key = f"{msg.get('id')}|{d.get('requestId')}"
            r = recs.get(key)
            if r is None:
                r = recs[key] = {"t": d["timestamp"], "model": model, "u": u, "cwd": d.get("cwd"),
                                 "session": d.get("sessionId"), "entry": d.get("entrypoint") or "?",
                                 "effort": d.get("effort"), "side": bool(d.get("isSidechain")),
                                 "tools": {}, "stop": msg.get("stop_reason")}
            else:
                r["u"] = u
                r["stop"] = msg.get("stop_reason") or r["stop"]
            for c in msg.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    r["tools"][c.get("id") or str(len(r["tools"]))] = c.get("name") or "?"
    # porządki: tylko ostatnie ~31 dni i istniejące pliki
    keep_after = datetime.now(timezone.utc) - timedelta(days=32)
    n_recs, n_files = len(recs), len(files)
    cache["recs"] = recs = {k: v for k, v in recs.items() if _dt(v["t"]) >= keep_after}
    cache["files"] = {p_: v for p_, v in files.items() if os.path.exists(p_)}
    if dirty or len(recs) != n_recs or len(cache["files"]) != n_files:
        tmp = RECORDS_CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cache, f, separators=(",", ":"))
        os.replace(tmp, RECORDS_CACHE)

    out = []
    for v in recs.values():
        t = _dt(v["t"])
        if t < since:
            continue
        out.append({"t": t, "model": v["model"], "u": v["u"], "cwd": v["cwd"], "session": v["session"],
                    "entry": v["entry"], "effort": v["effort"], "side": v["side"],
                    "tools": list(v["tools"].values()), "stop": v["stop"]})
    return sorted(out, key=lambda r: r["t"])


def _tok(u):
    cc = u.get("cache_creation") or {}
    cw = (u.get("cache_creation_input_tokens") or 0)
    return {
        "in": u.get("input_tokens") or 0,
        "out": u.get("output_tokens") or 0,
        "cr": u.get("cache_read_input_tokens") or 0,
        "cw": cw,
        "think": ((u.get("output_tokens_details") or {}).get("thinking_tokens") or 0),
        "web": ((u.get("server_tool_use") or {}).get("web_search_requests") or 0)
               + ((u.get("server_tool_use") or {}).get("web_fetch_requests") or 0),
    }


def _empty():
    return {"responses": 0, "in": 0, "out": 0, "cr": 0, "cw": 0, "think": 0, "cost": 0.0, "tools": 0, "web": 0}


def _add(acc, r):
    k = r["k"]
    acc["responses"] += 1
    for f in ("in", "out", "cr", "cw", "think", "web"):
        acc[f] += k[f]
    acc["cost"] += r["cost"]
    acc["tools"] += len(r["tools"])


def _round(acc):
    acc["cost"] = round(acc["cost"], 2)
    return acc


def maybe_analytics(out, now):
    try:
        if time.time() - os.path.getmtime(ANALYTICS) < ANALYTICS_EVERY and "--now" not in sys.argv:
            return
    except OSError:
        pass
    data = compute_analytics(out, now)
    tmp = ANALYTICS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, ANALYTICS)


def compute_analytics(out, now):
    since = (now - timedelta(days=30)).astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    recs = load_records(since)
    for r in recs:
        r["k"] = _tok(r["u"])
        r["cost"] = _cost(r["model"], r["u"])
        r["local"] = r["t"].astimezone()
        r["project"] = _project_name(r["cwd"])

    local_now = now.astimezone()
    today = local_now.date()
    periods = {"today": today, "d7": today - timedelta(days=6), "d30": today - timedelta(days=29)}
    totals = {}
    for name, start in periods.items():
        acc = _empty()
        sessions, projects = set(), set()
        for r in recs:
            if r["local"].date() >= start:
                _add(acc, r)
                sessions.add(r["session"]); projects.add(r["project"])
        acc["sessions"] = len(sessions)
        acc["projects"] = len(projects)
        totals[name] = _round(acc)
    # poprzednie 7 dni — do porównania trendu
    prev = _empty()
    for r in recs:
        if today - timedelta(days=13) <= r["local"].date() < today - timedelta(days=6):
            _add(prev, r)
    totals["prev7"] = _round(prev)

    # dzień po dniu
    daily = {}
    for i in range(29, -1, -1):
        d = (today - timedelta(days=i)).isoformat()
        daily[d] = dict(_empty(), date=d, sessions=set(), models={})
    for r in recs:
        d = daily.get(r["local"].date().isoformat())
        if d is None:
            continue
        _add(d, r)
        d["sessions"].add(r["session"])
        fam = _family(r["model"])
        d["models"][fam] = d["models"].get(fam, 0.0) + r["cost"]
    daily_list = []
    for d in daily.values():
        d["sessions"] = len(d["sessions"])
        d["models"] = {k: round(v, 3) for k, v in d["models"].items()}
        daily_list.append(_round(d))

    # mapa ciepła: dzień tygodnia × godzina
    heat = [[0.0] * 24 for _ in range(7)]
    heat_n = [[0] * 24 for _ in range(7)]
    for r in recs:
        heat[r["local"].weekday()][r["local"].hour] += r["cost"]
        heat_n[r["local"].weekday()][r["local"].hour] += 1

    # modele
    models = {}
    for r in recs:
        m = models.setdefault(r["model"], dict(_empty(), model=r["model"], family=_family(r["model"])))
        _add(m, r)
    total_cost = sum(r["cost"] for r in recs) or 1e-9
    model_list = []
    for m in models.values():
        pin, pout, pread = _price(m["model"])
        m["share"] = round(m["cost"] / total_cost, 4)
        m["avgOut"] = round(m["out"] / m["responses"]) if m["responses"] else 0
        m["cacheHit"] = round(m["cr"] / max(1, m["in"] + m["cr"] + m["cw"]), 4)
        model_list.append(_round(m))
    model_list.sort(key=lambda m: -m["cost"])

    # projekty
    projects = {}
    for r in recs:
        p = projects.setdefault(r["project"], dict(_empty(), name=r["project"], path=r["cwd"], sessions=set(),
                                                   last=r["t"], models={}))
        _add(p, r)
        p["sessions"].add(r["session"])
        p["last"] = max(p["last"], r["t"])
        fam = _family(r["model"])
        p["models"][fam] = p["models"].get(fam, 0) + r["cost"]
    proj_list = []
    for p in projects.values():
        p["sessions"] = len(p["sessions"])
        p["last"] = p["last"].isoformat()
        p["share"] = round(p["cost"] / total_cost, 4)
        p["topModel"] = max(p["models"], key=p["models"].get) if p["models"] else None
        del p["models"]
        proj_list.append(_round(p))
    proj_list.sort(key=lambda p: -p["cost"])

    # sesje
    sess = {}
    for r in recs:
        s_ = sess.setdefault(r["session"], {"id": r["session"], "project": r["project"], "start": r["t"], "end": r["t"],
                                             "cost": 0.0, "responses": 0, "times": [], "models": {}, "entry": r["entry"]})
        s_["end"] = max(s_["end"], r["t"])
        s_["cost"] += r["cost"]
        s_["responses"] += 1
        s_["times"].append(r["t"])
        fam = _family(r["model"])
        s_["models"][fam] = s_["models"].get(fam, 0) + r["cost"]
    sess_list = []
    for s_ in sess.values():
        ts = sorted(s_["times"])
        # aktywny czas: przerwy dłuższe niż 15 min liczymy jako 1 min
        gaps = ((b - a).total_seconds() for a, b in zip(ts, ts[1:]))
        active = sum(g if g < 900 else 60 for g in gaps) + 60
        sess_list.append({"id": s_["id"], "project": s_["project"], "start": s_["start"].isoformat(),
                          "end": s_["end"].isoformat(), "cost": round(s_["cost"], 2), "responses": s_["responses"],
                          "activeMin": round(active / 60), "entry": s_["entry"],
                          "topModel": max(s_["models"], key=s_["models"].get)})
    actives = sorted(x["activeMin"] for x in sess_list)
    resp = sorted(x["responses"] for x in sess_list)
    sessions_summary = {
        "count": len(sess_list),
        "medianActiveMin": _quantile(actives, 0.5) if actives else 0,
        "p90ActiveMin": _quantile(actives, 0.9) if actives else 0,
        "medianResponses": _quantile(resp, 0.5) if resp else 0,
        "totalActiveHours": round(sum(actives) / 60, 1),
        "top": sorted(sess_list, key=lambda x: -x["cost"])[:8],
    }

    # narzędzia
    tools = {}
    for r in recs:
        for t in r["tools"]:
            g = _tool_group(t)
            tools[g] = tools.get(g, 0) + 1
    tool_list = sorted(({"name": k, "count": v} for k, v in tools.items()), key=lambda x: -x["count"])

    # źródła (aplikacje), wysiłek, podagenci, zatrzymania
    def group(keyf):
        g = {}
        for r in recs:
            k = keyf(r) or "?"
            a = g.setdefault(k, {"name": k, "cost": 0.0, "responses": 0})
            a["cost"] += r["cost"]; a["responses"] += 1
        lst = sorted(g.values(), key=lambda x: -x["cost"])
        for a in lst:
            a["cost"] = round(a["cost"], 2); a["share"] = round(a["cost"] / total_cost, 4)
        return lst
    entry_names = {"cli": "Terminal (CLI)", "claude-desktop": "Aplikacja desktop", "claude-vscode": "VS Code",
                   "sdk-cli": "SDK", "sdk-ts": "SDK (TS)", "sdk-py": "SDK (Python)"}
    entries = group(lambda r: entry_names.get(r["entry"], r["entry"]))
    efforts = group(lambda r: r["effort"] or "domyślny")
    sidechain = group(lambda r: "Podagenci" if r["side"] else "Główna rozmowa")
    stops = {}
    for r in recs:
        stops[r["stop"] or "?"] = stops.get(r["stop"] or "?", 0) + 1

    # cache: trafienia i oszczędność
    t30 = totals["d30"]
    inp_all = t30["in"] + t30["cr"] + t30["cw"]
    saved = sum(r["k"]["cr"] * (_price(r["model"])[0] - _price(r["model"])[2]) / 1e6 for r in recs)
    cache = {"hitRate": round(t30["cr"] / max(1, inp_all), 4), "savedUSD": round(saved, 2),
             "writeUSD": round(sum(r["k"]["cw"] * _price(r["model"])[0] * 1.5 / 1e6 for r in recs), 2),
             "contextPerResponse": round(inp_all / max(1, t30["responses"]))}

    # kalibracja: ile % limitu tygodnia kosztuje 1 $ (tylko część z Claude Code)
    calib = None
    fresh = out.get("status") == "ok"
    w = _win(out, "seven_day")
    if fresh and w and w.get("resetsAt"):
        wstart = _dt(w["resetsAt"]) - WEEK
        week_cost = sum(r["cost"] for r in recs if r["t"] >= wstart)
        cc_share = next((s_["percent"] for s_ in out.get("sources") or [] if s_["name"] == "Claude Code"), None)
        cc_pct = w["percent"] * (cc_share / 100 if cc_share is not None else 1)
        if week_cost > 0.5 and cc_pct > 0.5:
            k = cc_pct / week_cost
            calib = {"pctPerUSD": round(k, 4), "weekValueUSD": round(100 / k, 0), "weekCostUSD": round(week_cost, 2),
                     "claudeCodePct": round(cc_pct, 1), "measuredAt": now.isoformat()}
    if calib is None:
        # na początku tygodnia za mało danych — zostaje ostatni znany przelicznik
        try:
            with open(ANALYTICS) as f:
                calib = json.load(f).get("calibration")
        except (OSError, ValueError):
            pass
        if calib is None and BACKFILL and os.path.exists(BACKFILL):
            try:
                with open(BACKFILL) as f:
                    k = json.load(f)["factor"]
                calib = {"pctPerUSD": round(k, 4), "weekValueUSD": round(100 / k, 0), "weekCostUSD": 0,
                         "claudeCodePct": 0, "measuredAt": None}
            except (OSError, ValueError, KeyError):
                pass

    # okna 5h odtworzone z logów
    windows5 = []
    cur = None
    for r in recs:
        if cur is None or r["t"] >= cur["end"]:
            st = r["t"].replace(minute=0, second=0, microsecond=0)
            cur = {"start": st, "end": st + timedelta(hours=5), "cost": 0.0, "responses": 0, "last": r["t"]}
            windows5.append(cur)
        cur["cost"] += r["cost"]; cur["responses"] += 1; cur["last"] = r["t"]
    f5 = None
    fh = _win(out, "five_hour")
    if fh and fh.get("resetsAt") and windows5:
        fr = _dt(fh["resetsAt"])
        cost_now = sum(r["cost"] for r in recs if fr - timedelta(hours=5) <= r["t"] < fr)
        cc_share = next((s_["percent"] for s_ in out.get("sources") or [] if s_["name"] == "Claude Code"), 100) / 100
        if fresh and cost_now > 0.2 and fh["percent"] > 1:
            f5 = fh["percent"] * cc_share / cost_now
    if f5 is None:
        try:
            with open(ANALYTICS) as f:
                f5 = json.load(f).get("fiveHourFactor")
        except (OSError, ValueError):
            pass
    w5 = []
    for x in windows5:
        w5.append({"start": x["start"].isoformat(), "end": x["end"].isoformat(), "cost": round(x["cost"], 2),
                   "responses": x["responses"],
                   "activeMin": round((x["last"] - x["start"]).total_seconds() / 60),
                   "estPct": round(min(100.0, x["cost"] * f5), 1) if f5 else None})
    starts = [0] * 24
    for x in windows5:
        starts[x["start"].astimezone().hour] += 1

    try:
        timeline = week_timeline(out, now, recs)
    except Exception as e:
        timeline = {"error": f"{type(e).__name__}: {e}"}

    # wnioski
    insights = build_insights(totals, heat, model_list, proj_list, cache, sidechain, tool_list, stops, calib, sessions_summary)

    return {
        "generatedAt": now.isoformat(), "since": since.isoformat(),
        "totals": totals, "daily": daily_list,
        "heatmap": [[round(v, 3) for v in row] for row in heat], "heatmapResponses": heat_n,
        "models": model_list, "projects": proj_list[:15], "projectCount": len(proj_list),
        "sessions": sessions_summary, "tools": tool_list[:15], "toolTotal": sum(tools.values()),
        "entrypoints": entries, "efforts": efforts, "sidechain": sidechain,
        "stopReasons": stops, "cache": cache, "calibration": calib,
        "fiveHourWindows": w5[-60:], "fiveHourFactor": round(f5, 4) if f5 else None, "fiveHourStarts": starts,
        "insights": insights,
        "weekTimeline": timeline,
    }


STEP = timedelta(minutes=15)
IDLE_MIN = timedelta(hours=3)        # przerwa: co najmniej 3 h bez żadnej aktywności
INTENSE_PER_H = 2.0                  # duże zużycie: ≥ 2% limitu tygodnia na godzinę


def week_timeline(out, now, recs):
    """Oś czasu bieżącego tygodnia limitu w krokach 15 min.

    Prawdziwe odczyty serwera są podstawą. Czas przed pierwszym odczytem uzupełnia
    szacunek z lokalnych logów, przeskalowany tak, by kończył się DOKŁADNIE na pierwszym
    odczycie (bez skoków w dół). Wartość nigdy nie maleje w obrębie tygodnia.
    """
    w = _win(out, "seven_day")
    if not w or not w.get("resetsAt"):
        return None
    reset = _dt(w["resetsAt"])
    start = reset - WEEK
    hist = [r for r in load_history() if r.get("wr") and _same_window(r["wr"], w["resetsAt"])]
    real = [(_dt(r["t"]), float(r["w"])) for r in hist if start <= _dt(r["t"]) <= now]
    end = min(now, reset)

    # siatka 15-min
    grid = []
    t = start
    while t <= end:
        grid.append(t)
        t += STEP
    if not grid or grid[-1] < end:
        grid.append(end)

    # aktywność z logów (odpowiedzi Claude Code) w każdym kroku
    active_steps = set()
    step_cost = {}
    for r in recs:
        if start <= r["t"] <= end:
            i = int((r["t"] - start) / STEP)
            active_steps.add(i)
            step_cost[i] = step_cost.get(i, 0.0) + r["cost"]

    first_t, first_v = (real[0] if real else (end, float(w["percent"])))
    # szacunek przed pierwszym odczytem: skumulowany koszt przeskalowany do first_v
    est_total = sum(c for i, c in step_cost.items() if start + STEP * i < first_t)
    scale = first_v / est_total if est_total > 0 else None

    points = []
    cum_est = 0.0
    ri = 0
    last_real = None
    for i, gt in enumerate(grid):
        if gt < first_t:
            cum_est += step_cost.get(i - 1, 0.0) if i > 0 else 0.0
            if scale is not None:
                v = cum_est * scale
            else:  # brak logów — równomiernie do pierwszego odczytu
                v = first_v * ((gt - start) / (first_t - start)) if first_t > start else first_v
            points.append({"t": gt, "v": min(v, first_v), "est": True})
        else:
            while ri < len(real) and real[ri][0] <= gt:
                last_real = real[ri][1] if last_real is None else max(last_real, real[ri][1])
                ri += 1
            v = last_real if last_real is not None else first_v
            points.append({"t": gt, "v": v, "est": False})
    # dokładny punkt pierwszego odczytu i „teraz”
    if real:
        points.append({"t": first_t, "v": first_v, "est": False})
    points.append({"t": end, "v": max(float(w["percent"]), points[-1]["v"] if points else 0), "est": False})
    points.sort(key=lambda p: p["t"])
    # monotoniczność
    m = 0.0
    for p in points:
        m = max(m, p["v"])
        p["v"] = m

    # przyrost na krok i aktywność
    n = len(grid)
    gain = [0.0] * n
    vals = []
    j = 0
    for i, gt in enumerate(grid):
        while j + 1 < len(points) and points[j + 1]["t"] <= gt:
            j += 1
        vals.append(points[j]["v"])
    for i in range(1, n):
        gain[i] = max(0.0, vals[i] - vals[i - 1])
    active = [((i - 1) in active_steps) or gain[i] > 0.01 for i in range(n)]

    # przerwy
    idle = []
    i = 0
    while i < n:
        if not active[i]:
            k = i
            while k < n and not active[k]:
                k += 1
            a, b = grid[max(0, i - 1)], grid[k - 1] if k - 1 < n else end
            if b - a >= IDLE_MIN:
                idle.append({"start": a.isoformat(), "end": b.isoformat(), "hours": round((b - a).total_seconds() / 3600, 1),
                             "ongoing": k >= n})
            i = k
        else:
            i += 1

    # duże zużycie: przyrost w oknie 1 h ≥ INTENSE_PER_H
    per_step = 4
    hot = [False] * n
    for i in range(n):
        lo = max(0, i - per_step + 1)
        if vals[i] - vals[lo] >= INTENSE_PER_H * (i - lo) / per_step and i - lo >= 2:
            for x in range(lo, i + 1):
                hot[x] = True
    # sklej okresy oddzielone przerwą ≤ 1 h
    for i in range(n):
        if not hot[i] and any(hot[max(0, i - 4):i]) and any(hot[i + 1:i + 5]):
            hot[i] = True
    intense = []
    i = 0
    while i < n:
        if hot[i]:
            k = i
            while k < n and hot[k]:
                k += 1
            a, b = grid[i], grid[k - 1]
            g = vals[k - 1] - vals[i]
            hours = max(0.25, (b - a).total_seconds() / 3600)
            if g >= 2:
                est = any(p["est"] for p in points if a <= p["t"] <= b)
                intense.append({"start": a.isoformat(), "end": b.isoformat(), "gain": round(g, 1),
                                "hours": round(hours, 1), "perHour": round(g / hours, 1), "est": est})
            i = k
        else:
            i += 1

    # dni: przyrost w każdym dniu lokalnym
    days = []
    day0 = start.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    d = day0
    while d < end.astimezone():
        nd = d + timedelta(days=1)
        a_, b_ = max(d, start.astimezone()), min(nd, end.astimezone())
        va = _value_at(points, a_)
        vb = _value_at(points, b_)
        est_day = any(p["est"] for p in points if a_ <= p["t"] < b_)
        act_h = sum(1 for i2, gt in enumerate(grid) if a_ <= gt < b_ and active[i2]) * 0.25
        days.append({"date": d.date().isoformat(), "gain": round(vb - va, 1), "est": est_day,
                     "activeHours": round(act_h, 1), "partial": b_ < nd})
        d = nd

    # najszybsza godzina
    best = None
    for i in range(per_step, n):
        g = vals[i] - vals[i - per_step]
        if best is None or g > best[0]:
            best = (g, grid[i - per_step], grid[i])
    peak = {"start": best[1].isoformat(), "end": best[2].isoformat(), "gain": round(best[0], 1)} if best and best[0] > 0 else None

    # odchudzone punkty: tylko zmiany wartości/statusu + co godzinę
    slim = []
    for p in points:
        if not slim or p["v"] != slim[-1]["v"] or p["est"] != slim[-1]["est"] or (p["t"] - _dt(slim[-1]["t"])) >= timedelta(hours=1):
            slim.append({"t": p["t"].isoformat(), "v": round(p["v"], 2), "est": p["est"]})
    if slim and slim[-1]["t"] != points[-1]["t"].isoformat():
        slim.append({"t": points[-1]["t"].isoformat(), "v": round(points[-1]["v"], 2), "est": points[-1]["est"]})

    return {"start": start.isoformat(), "reset": reset.isoformat(), "firstReading": first_t.isoformat() if real else None,
            "estimatedUntil": first_t.isoformat() if real and first_t > start else None,
            "points": slim, "idle": idle, "intense": intense, "days": days, "peakHour": peak,
            "activeHours": round(sum(active) * 0.25, 1)}


def _value_at(points, t):
    v = 0.0
    for p in points:
        if p["t"] <= t:
            v = p["v"]
        else:
            break
    return v


def _family(model):
    for fam in ("fable", "mythos", "opus", "sonnet", "haiku"):
        if fam in model:
            return fam.capitalize()
    return model


def build_insights(totals, heat, models, projects, cache, sidechain, tools, stops, calib, sess):
    tips = []
    k = calib["pctPerUSD"] if calib else None
    t30, t7, p7 = totals["d30"], totals["d7"], totals["prev7"]

    def lim(usd):
        v = usd * k
        return (f"{v:.1f}" if v < 10 else f"{v:.0f}").replace(".", ",") + "%"

    if t30["cost"] > 0:
        txt = f"W 30 dni Claude Code przetworzył {_fmt_tokens(t30['in'] + t30['cr'] + t30['cw'] + t30['out'])} tokenów"
        if k:
            weeks = t30["cost"] * k / 100
            txt += f" — to ok. {lim(t30['cost'])} limitu tygodniowego (≈ {str(round(weeks, 1)).replace('.', ',')} tyg. limitu)."
        tips.append({"icon": "sum", "tone": "info", "text": txt if txt.endswith(".") else txt + "."})
    if p7["cost"] > 0.5:
        ch = (t7["cost"] - p7["cost"]) / p7["cost"] * 100
        tips.append({"icon": "arrow.up.right" if ch >= 0 else "arrow.down.right",
                     "tone": "warn" if ch > 40 else "info",
                     "text": f"Ostatnie 7 dni: {'+' if ch >= 0 else ''}{ch:.0f}% zużycia względem poprzedniego tygodnia."})
    best, bw, bh = 0, 0, 0
    for wd in range(7):
        for h in range(24):
            v = heat[wd][h] + heat[wd][(h + 1) % 24]
            if v > best:
                best, bw, bh = v, wd, h
    if best > 0:
        tips.append({"icon": "flame.fill", "tone": "info",
                     "text": f"Najintensywniej pracujesz w {PL_WEEKDAYS[bw]} między {bh}:00 a {(bh + 2) % 24}:00."})
    night = sum(heat[wd][h] for wd in range(7) for h in range(0, 6))
    total = sum(map(sum, heat)) or 1
    if night / total > 0.15:
        tips.append({"icon": "moon.stars.fill", "tone": "info",
                     "text": f"{night / total * 100:.0f}% zużycia przypada na noc (0–6)."})
    if models:
        m = models[0]
        tips.append({"icon": "cpu.fill", "tone": "info",
                     "text": f"{_family(m['model'])} odpowiada za {m['share'] * 100:.0f}% zużycia (średnio {m['avgOut']} tokenów odpowiedzi)."})
    if cache["hitRate"] > 0 and t30["cost"] > 0:
        mult = (t30["cost"] + cache["savedUSD"]) / t30["cost"]
        tips.append({"icon": "bolt.fill", "tone": "good",
                     "text": f"Cache obsłużył {cache['hitRate'] * 100:.0f}% kontekstu — bez niego te same zadania zużyłyby ok. {mult:.0f}× więcej."})
    if projects:
        p = projects[0]
        tips.append({"icon": "folder.fill", "tone": "info",
                     "text": f"Najbardziej wymagający projekt: „{p['name']}” — {p['share'] * 100:.0f}% zużycia"
                             + (f" ({lim(p['cost'])} limitu tygodnia)" if k else "") + f", {p['sessions']} sesji."})
    side = next((x for x in sidechain if x["name"] == "Podagenci"), None)
    if side and side["share"] > 0.05:
        tips.append({"icon": "person.2.fill", "tone": "info",
                     "text": f"Podagenci zużyli {side['share'] * 100:.0f}% — przy równoległych zadaniach limit topnieje szybciej."})
    trunc = stops.get("max_tokens", 0)
    if trunc:
        tips.append({"icon": "scissors", "tone": "warn", "text": f"{trunc} odpowiedzi ucięto na limicie długości (max_tokens)."})
    if k and t30["cost"] > 0 and t30["responses"]:
        per = t30["responses"] / (t30["cost"] * k)
        tips.append({"icon": "scalemass.fill", "tone": "good",
                     "text": f"1% limitu tygodniowego to średnio ok. {per:.0f} odpowiedzi Claude Code."})
    if sess["count"]:
        tips.append({"icon": "timer", "tone": "info",
                     "text": f"{sess['count']} sesji, łącznie ok. {sess['totalActiveHours']:.0f} h aktywnej pracy; typowa sesja ~{sess['medianActiveMin']:.0f} min."})
    return tips


def _fmt_tokens(n):
    if n >= 1e9:
        return f"{n / 1e9:.1f} mld".replace(".", ",")
    if n >= 1e6:
        return f"{n / 1e6:.1f} mln".replace(".", ",")
    if n >= 1e3:
        return f"{n / 1e3:.0f} tys."
    return str(n)


if __name__ == "__main__":
    main()
