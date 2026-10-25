"""Muse price watch: re-check what the group might book, remember every price, and speak up when it matters.

Each watch is one thing a plan might pay for (a flight route, a hotel, a used-car search). `check` asks SerpApi again
(fresh, never cached), stores the price, and when it moves past THRESHOLD asks Muse Spark whether to book now, wait,
or keep watching. That advice becomes an alert the app turns into a notification, and the plan's Budget Tracker sheet
is rewritten with the new number.

Prices are per person for flights, per room per night for hotels, and per car for listings.
"""
import json
import os
import re
import sqlite3
import time
import uuid
from datetime import date

from . import serp
from .muse import muse

DB = os.environ.get("HUDDLE_DB", "huddle.db")
# Alert when a price moves at least this share of the last price, and at least MIN_MOVE dollars.
THRESHOLD = float(os.environ.get("HUDDLE_WATCH_THRESHOLD", "0.03"))
MIN_MOVE = float(os.environ.get("HUDDLE_WATCH_MIN_MOVE", "5"))


def _db():
    c = sqlite3.connect(DB, timeout=15)  # parallel checks write at the same moment
    c.row_factory = sqlite3.Row
    c.execute("""create table if not exists watches (
        id text primary key, plan_id text not null, category text not null, label text not null,
        detail text not null default '', unit text not null default '', engine text not null,
        params text not null, match text not null default '', needed_by text, baseline real,
        created real not null)""")
    c.execute("create table if not exists prices (watch_id text not null, at real not null, price real not null)")
    c.execute("""create table if not exists alerts (
        id text primary key, watch_id text not null, plan_id text not null, at real not null,
        old real not null, new real not null, verdict text not null, headline text not null, reason text not null)""")
    c.execute("""create table if not exists budget_sheets (
        plan_id text primary key, url text not null, travelers integer not null, cap real)""")
    return c


# MARK: - Reading a price out of a search


def price_of(engine, data, match="", adults=1):
    """The watched price from one SerpApi response, or None if it isn't there."""
    if engine == "google_flights":
        prices = [o["price"] for o in data.get("best_flights", []) + data.get("other_flights", []) if o.get("price")]
        if match:
            prices = [o["price"] for o in data.get("best_flights", []) + data.get("other_flights", [])
                      if o.get("price") and any(match.lower() in l.get("airline", "").lower() for l in o.get("flights", []))] or prices
        return min(prices) / adults if prices else None
    if engine == "google_hotels":
        props = [p for p in data.get("properties", []) if p.get("rate_per_night", {}).get("extracted_lowest")]
        named = [p for p in props if match and match.lower() in p["name"].lower()]
        pick = named[0] if named else (min(props, key=lambda p: p["rate_per_night"]["extracted_lowest"]) if props and not match else None)
        return pick["rate_per_night"]["extracted_lowest"] if pick else None
    if engine == "google_shopping":
        prices = [i["extracted_price"] for i in data.get("shopping_results", []) if i.get("extracted_price")]
        return min(prices) if prices else None
    return None


def history_from(data, adults=1):
    """Google Flights' own price history ([[unix, price], ...]) so a new watch isn't blank."""
    return [(t, p / adults) for t, p in data.get("price_insights", {}).get("price_history", [])]


def typical_range(data, adults=1):
    r = data.get("price_insights", {}).get("typical_price_range")
    return [r[0] / adults, r[1] / adults] if r else None


# MARK: - Watches


def create(plan_id, category, label, engine, params, match="", detail="", unit="", needed_by=None, price=None, seed=None):
    """Start watching. `seed` is a SerpApi response to take the starting price and history from."""
    wid = uuid.uuid4().hex[:10]
    adults = int(params.get("adults", 1)) if engine == "google_flights" else 1
    now = time.time()
    if seed is not None and price is None:
        price = price_of(engine, seed, match, adults)
    with _db() as c:
        c.execute("insert into watches values (?,?,?,?,?,?,?,?,?,?,?,?)",
                  (wid, plan_id, category, label, detail, unit, engine, json.dumps(params), match, needed_by, price, now))
        if seed is not None:
            for t, p in history_from(seed, adults):
                if t < now:
                    c.execute("insert into prices values (?,?,?)", (wid, t, p))
        if price is not None:
            c.execute("insert into prices values (?,?,?)", (wid, now, price))
    return get(wid)


def find(plan_id, engine, params, match=""):
    with _db() as c:
        row = c.execute("select id from watches where plan_id=? and engine=? and params=? and match=?",
                        (plan_id, engine, json.dumps(params), match)).fetchone()
    return get(row["id"]) if row else None


def get(wid):
    with _db() as c:
        w = c.execute("select * from watches where id=?", (wid,)).fetchone()
        if not w:
            return None
        prices = c.execute("select at, price from prices where watch_id=? order by at", (wid,)).fetchall()
        alert = c.execute("select * from alerts where watch_id=? order by at desc limit 1", (wid,)).fetchone()
    history = [[round(p["at"]), p["price"]] for p in prices]
    values = [p for _, p in history]
    return {
        "id": w["id"], "planId": w["plan_id"], "category": w["category"], "label": w["label"], "detail": w["detail"],
        "unit": w["unit"], "neededBy": w["needed_by"], "baseline": w["baseline"],
        "current": values[-1] if values else None, "low": min(values) if values else None,
        "high": max(values) if values else None, "history": history[-40:],
        "checkedAt": history[-1][0] if history else None,
        "advice": _alert_json(alert) if alert else None,
    }


def for_plan(plan_id):
    with _db() as c:
        ids = [r["id"] for r in c.execute("select id from watches where plan_id=? order by created", (plan_id,))]
    return [get(i) for i in ids]


def remove(wid):
    with _db() as c:
        c.execute("delete from watches where id=?", (wid,))
        c.execute("delete from prices where watch_id=?", (wid,))
        c.execute("delete from alerts where watch_id=?", (wid,))


def _alert_json(a):
    return {"id": a["id"], "watchId": a["watch_id"], "planId": a["plan_id"], "at": round(a["at"]), "old": a["old"],
            "new": a["new"], "verdict": a["verdict"], "headline": a["headline"], "reason": a["reason"]}


def alerts(since=0.0, plan_id=None):
    q, args = "select * from alerts where at > ?", [since]
    if plan_id:
        q, args = q + " and plan_id = ?", args + [plan_id]
    with _db() as c:
        return [_alert_json(a) for a in c.execute(q + " order by at", args)]


# MARK: - Checking


def moved(old, new):
    return abs(new - old) >= max(MIN_MOVE, THRESHOLD * old)


def days_until(needed_by):
    if not needed_by:
        return None
    try:
        return (date.fromisoformat(needed_by) - date.today()).days
    except ValueError:
        return None


def advise(w, old, new, typical=None):
    facts = {"item": w["label"], "unit": w["unit"], "previous": old, "current": new, "lowest_seen": min(w["low"] or new, new),
             "highest_seen": max(w["high"] or new, new), "days_until": days_until(w["neededBy"]),
             "recent_prices": [p for _, p in w["history"][-10:]]}
    if typical:
        facts["typical_range"] = typical
    from .muse import MockMuse
    rule = MockMuse().advise(facts)
    if isinstance(muse, MockMuse):
        return rule
    new_low = new < old and new <= facts["lowest_seen"] + 0.5
    # Muse gets dollar amounts written out, so its reasons say "$1,148", not "1148.0".
    dollars = lambda v: f"${v:,.0f}"
    shown = {**facts, "previous": dollars(old), "current": dollars(new), "lowest_seen": dollars(facts["lowest_seen"]),
             "highest_seen": dollars(facts["highest_seen"]), "recent_prices": [dollars(v) for v in facts["recent_prices"]],
             "change": f"{'down' if new < old else 'up'} {dollars(abs(new - old))}", "is_new_low": new_low}
    if typical:
        shown["typical_range"] = [dollars(v) for v in typical]
    try:
        out = muse.advise(shown)
    except Exception:
        return rule  # Muse is down or returned something odd: the rule of thumb still gives a fair heads-up
    if new_low and out["verdict"] != "book":
        return rule  # a drop to the lowest price seen is always worth acting on; keep the text consistent with that
    return out


def check(wid):
    """Ask SerpApi again. Returns the new alert if the price moved enough to mention, else None."""
    w = get(wid)
    if not w:
        return None
    with _db() as c:
        row = c.execute("select engine, params, match from watches where id=?", (wid,)).fetchone()
    engine, params, match = row["engine"], json.loads(row["params"]), row["match"]
    adults = int(params.get("adults", 1)) if engine == "google_flights" else 1
    data = serp.search(engine, fresh=True, **params)
    new = price_of(engine, data, match, adults)
    if new is None:
        return None
    new = round(new, 2)
    now = time.time()
    with _db() as c:
        c.execute("insert into prices values (?,?,?)", (wid, now, new))
    old = w["current"]
    if old is None or not moved(old, new):
        return None
    advice = advise(w, old, new, typical_range(data, adults))
    alert = {"id": uuid.uuid4().hex[:10], "watch_id": wid, "plan_id": w["planId"], "at": now, "old": old, "new": new, **advice}
    with _db() as c:
        c.execute("insert into alerts values (?,?,?,?,?,?,?,?,?)",
                  tuple(alert[k] for k in ("id", "watch_id", "plan_id", "at", "old", "new", "verdict", "headline", "reason")))
    try:
        update_budget(w["planId"], w, new, params)
    except Exception:
        pass  # the alert still goes out; the sheet catches up on the next move
    return _alert_json({**alert})


def check_plan(plan_id):
    """Re-check every watch on a plan at once. Each move asks Muse (several seconds), so one at a time could run past
    the app's 60-second timeout on a plan with many watches."""
    from concurrent.futures import ThreadPoolExecutor
    with _db() as c:
        ids = [r["id"] for r in c.execute("select id from watches where plan_id=?", (plan_id,))]
    with ThreadPoolExecutor(max_workers=min(6, max(1, len(ids)))) as pool:
        return [a for a in pool.map(check, ids) if a]


def check_all():
    with _db() as c:
        ids = [r["id"] for r in c.execute("select id from watches")]
    out = []
    for i in ids:
        try:
            if a := check(i):
                out.append(a)
        except Exception:
            continue  # one bad search shouldn't stop the rest
    return out


# MARK: - Budget Tracker


def register_budget(plan_id, url, travelers, cap=None):
    with _db() as c:
        c.execute("insert or replace into budget_sheets values (?,?,?,?)", (plan_id, url, travelers, cap))


def _dollars(text):
    m = re.search(r"-?[\d,]+(?:\.\d+)?", text or "")
    return float(m.group(0).replace(",", "")) if m else 0.0


def _money(n):
    return f"${n:,.0f}"


def nights(params):
    try:
        return (date.fromisoformat(params["check_out_date"]) - date.fromisoformat(params["check_in_date"])).days
    except (KeyError, ValueError):
        return 1


def revise(rows, w, price, params, travelers, cap=None):
    """Budget rows with the watched line set to the new price and the total redone. None if no line matches."""
    rows = [list(r) for r in rows]
    if w["category"] == "flights":
        # Only the airline the budget is built on ("Flights · ANA via LAX"), not every route being watched.
        airline = w["label"].split(" · ")[0].removesuffix(" (mock)").lower()
        hit = lambda item: item.startswith("Flights") and airline in item.lower()
        group = price * travelers
    elif w["category"] == "stays":
        name = w["label"].removesuffix(" (mock)").lower()
        hit = lambda item: item.lower().startswith(name) or name in item.lower()
        group = price * nights(params) * int(params.get("rooms", 1) or 1)
    else:
        return None
    lines = [i for i, r in enumerate(rows) if r and r[0] != "Total" and hit(r[0])]
    if not lines:
        return None
    i = lines[0]
    rows[i][1], rows[i][2] = _money(group / travelers), _money(group)
    total = sum(_dollars(r[2]) for r in rows if r and r[0] not in ("Total", ""))
    for r in rows:
        if r and r[0] == "Total":
            r[1], r[2] = _money(total / travelers), _money(total)
    if cap:
        diff = cap - total / travelers
        footer = f"{'Under' if diff >= 0 else 'Over'} the {_money(cap)} budget by {_money(abs(diff))} each · updated by Muse price watch"
    else:
        footer = f"Per person = group total ÷ {travelers} · updated by Muse price watch"
    return rows, footer


def update_budget(plan_id, w, price, params):
    with _db() as c:
        sheet = c.execute("select * from budget_sheets where plan_id=?", (plan_id,)).fetchone()
    if not sheet:
        return False
    drive = _drive_for(sheet["url"])
    columns, rows = drive.read_sheet(sheet["url"])
    out = revise(rows, w, price, params, sheet["travelers"], sheet["cap"])
    if not out:
        return False
    drive.update_sheet(sheet["url"], columns, *out)
    return True


def _drive_for(url):
    from . import google, workspace
    if url.startswith("file:"):
        return workspace.MockDrive()
    from .api import _refresh_token  # the same Google account that built the folder
    return google.Drive(_refresh_token())
