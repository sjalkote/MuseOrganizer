"""Plan folders: SerpApi research -> Muse-polished Sheets and Docs -> one shared Drive folder per plan.

The app posts its blueprint (call and file ids, engines, queries, folder name) and the build echoes those ids in its
progress events, so the app's progress list stays in step. Files the build knows how to research (the trip's Budget
Tracker, Daily and Places to stay + food; the car's Market prices, Dealer visit prep and Decision summary) are written
from search results; any other file is written as the app sent it.

With no Google credentials, MockDrive writes CSV and Markdown under fixtures/drive/<plan>/ instead.
"""
import csv
import os
import re
import shutil
import threading
import time
import urllib.parse
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

from . import serp
from .muse import muse

MOCK_ROOT = Path(os.environ.get("HUDDLE_DRIVE_DIR", Path(__file__).parent.parent / "fixtures" / "drive"))
# Mock builds pause between steps so the app's progress list visibly fills in.
PACE = float(os.environ.get("HUDDLE_MOCK_PACE", "0.25"))
BUILDS: dict[str, "Build"] = {}
MONTHS = {m: i for i, m in enumerate(["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}
DATES = re.compile(r"([A-Z][a-z]{2}) (\d{1,2})\s*[–-]\s*(?:([A-Z][a-z]{2}) )?(\d{1,2})")
FOOD_WORDS = ("food", "eat", "ramen", "izakaya", "sushi", "restaurant", "dinner", "lunch", "breakfast", "cafe", "bar")
PRICE_LEVEL = {"$": 20, "$$": 40, "$$$": 80, "$$$$": 150}  # rough dollars per person per meal day


class Cancelled(Exception):
    pass


@dataclass
class Build:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    events: list = field(default_factory=list)  # (kind, data); readers follow by index
    done: bool = False
    cancelled: bool = False

    def emit(self, event, **data):
        self.events.append((event, data))

    def check(self):
        if self.cancelled:
            raise Cancelled


def start(plan, make_drive, pace=None, on_done=None):
    """Run a build in the background; `make_drive` is called on the worker thread (it may hit the network).
    `on_done(plan, files)` runs after a successful build."""
    b = Build()
    BUILDS[b.id] = b
    threading.Thread(target=run, args=(b, plan, make_drive, pace, on_done), daemon=True).start()
    return b


# MARK: - Mock Drive


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "plan"


class MockDrive:
    mock = True

    def __init__(self, root=None):
        self.root = Path(root or MOCK_ROOT)

    def create_folder(self, name):
        path = self.root / slug(name)
        shutil.rmtree(path, ignore_errors=True)
        path.mkdir(parents=True)
        return str(path)

    def create_sheet(self, folder, title, columns, rows, footer=None):
        path = Path(folder) / f"{title}.csv"
        with path.open("w", newline="") as f:
            w = csv.writer(f)
            w.writerows([columns, *rows, *([[], [footer]] if footer else [])])
        return path.as_uri()

    def create_doc(self, folder, title, blocks):
        lines, prev = [], None
        for b in blocks:
            if lines and not (prev == b["type"] == "bullet"):
                lines.append("")
            lines.append({"title": "# ", "heading": "## ", "bullet": "- "}.get(b["type"], "") + b["text"])
            prev = b["type"]
        path = Path(folder) / f"{title}.md"
        path.write_text("\n".join(lines) + "\n")
        return path.as_uri()

    @staticmethod
    def path_of(url):
        return Path(urllib.parse.unquote(urllib.parse.urlparse(url).path))

    def read_sheet(self, url):
        """(columns, rows) from a sheet this drive wrote; the footer after the blank row is left out."""
        with self.path_of(url).open(newline="") as f:
            values = list(csv.reader(f))
        rows = []
        for r in values[1:]:
            if not any(r):
                break
            rows.append(r)
        return values[0], rows

    def update_sheet(self, url, columns, rows, footer=None):
        with self.path_of(url).open("w", newline="") as f:
            csv.writer(f).writerows([columns, *rows, *([[], [footer]] if footer else [])])

    def share(self, folder):
        return f"https://drive.google.com/drive/folders/huddle-mock-{Path(folder).name}"

    def delete(self, folder):
        shutil.rmtree(folder, ignore_errors=True)


# MARK: - Search params


def date_range(text, year):
    m = DATES.search(text)
    if not m:
        return None
    m1, d1, m2, d2 = m.groups()
    start = date(year, MONTHS[m1], int(d1))
    end = date(year, MONTHS[m2 or m1], int(d2))
    return start, end if end >= start else end.replace(year=year + 1)


def _number(pattern, text, default):
    m = re.search(pattern, text)
    return int(m.group(1)) if m else default


def plan_year(plan):
    ctx = plan.get("context", {})
    if ctx.get("year"):
        return int(ctx["year"])
    m = re.search(r"\b(20\d\d)\b", plan["folderName"] + " " + ctx.get("planName", ""))
    return int(m.group(1)) if m else date.today().year


def travelers(plan):
    for c in plan["calls"]:
        if c["engine"] == "google_flights":
            return _number(r"(\d+)\s*adults?", c["query"], 1)
    return len(plan.get("members", [])) or 1


def search_params(call, plan):
    q, engine, year = call["query"], call["engine"], plan_year(plan)
    if engine == "google_flights":
        airports = re.match(r"\s*([A-Z]{3})\s*(?:→|->|to)\s*([A-Z]{3})", q)
        dates = date_range(q, year)
        if not (airports and dates):
            raise ValueError(f"can't read airports and dates from the flight search {q!r}; send params with it")
        params = {"departure_id": airports[1], "arrival_id": airports[2], "outbound_date": dates[0].isoformat(),
                  "return_date": dates[1].isoformat(), "adults": _number(r"(\d+)\s*adults?", q, 1),
                  "currency": "USD", "hl": "en"}
    elif engine == "google_hotels":
        dates = date_range(q, year)
        if not dates:
            raise ValueError(f"can't read dates from the hotel search {q!r}; send params with it")
        params = {"q": q.split(",")[0].strip() + " hotels", "check_in_date": dates[0].isoformat(),
                  "check_out_date": dates[1].isoformat(), "adults": travelers(plan), "currency": "USD", "hl": "en"}
    else:
        params = {"q": q}
    return {**params, **call.get("params", {})}


def count_label(engine, data):
    if engine == "google_flights":
        return f"{len(data.get('best_flights', [])) + len(data.get('other_flights', []))} itineraries"
    key, noun = {"google_hotels": ("properties", "properties"), "google_maps": ("local_results", "places"),
                 "google_shopping": ("shopping_results", "listings")}.get(engine, ("organic_results", "results"))
    return f"{len(data.get(key, []))} {noun}"


# MARK: - Reading results


def money(n):
    return f"${n:,.0f}"


def day_label(d):
    return f"{d:%b} {d.day}"


def first_price(results):
    for r in results.get("organic_results", []):
        m = re.search(r"\$\s?([\d,]+(?:\.\d+)?)", r.get("snippet", "") + " " + r.get("title", ""))
        if m:
            return float(m.group(1).replace(",", ""))


def first_rate(results):
    for r in results.get("organic_results", []):
        m = re.search(r"(\d+(?:\.\d+)?)\s*%\s*APR", r.get("snippet", "") + " " + r.get("title", ""), re.I)
        if m:
            return m.group(1)


def area_of(query):
    return query.split(",")[-1].strip() if "," in query else query


def clock(stamp):
    t = datetime.strptime(stamp, "%Y-%m-%d %H:%M")
    return t.strftime("%I:%M %p").lstrip("0")


class Research:
    """The plan's search results, keyed by call, with the trip facts pulled out."""

    def __init__(self, plan, results):
        self.plan, self.results = plan, results
        self.calls = plan["calls"]
        self.year = plan_year(plan)
        self.travelers = travelers(plan)

    def of(self, engine):
        return [(c, self.results[c["id"]]) for c in self.calls if c["engine"] == engine]

    def flight(self):
        for call, data in self.of("google_flights"):
            options = data.get("best_flights") or data.get("other_flights") or []
            if options:
                return call, options[0]
        return None, None

    def trip_dates(self):
        call, _ = self.flight()
        dates = call and date_range(call["query"], self.year)
        if dates:
            return dates
        stays = self.stays()
        return (stays[0]["check_in"], stays[-1]["check_out"]) if stays else (None, None)

    def stays(self):
        out = []
        for call, data in self.of("google_hotels"):
            priced = [p for p in data.get("properties", []) if p.get("rate_per_night", {}).get("extracted_lowest")]
            if not priced:
                continue
            pick = max(priced[:5], key=lambda p: p.get("overall_rating", 0))  # best rated of Google's top five
            check_in, check_out = date_range(call["query"], self.year)
            out.append({"area": call["query"].split(",")[0].strip(), "name": pick["name"],
                        "rating": pick.get("overall_rating"), "rate": pick["rate_per_night"]["extracted_lowest"],
                        "check_in": check_in, "check_out": check_out,
                        "nights": (check_out - check_in).days, "rooms": _number(r"(\d+)\s*rooms?", call["query"], 1)})
        return sorted(out, key=lambda s: s["check_in"])

    def places(self, food):
        """[(area, [places])] from the Maps searches that are (food=True) or aren't about eating."""
        out = []
        for call, data in self.of("google_maps"):
            if any(w in call["query"].lower() for w in FOOD_WORDS) == food:
                out.append((area_of(call["query"]), list(data.get("local_results", []))))
        return out


def near(area, groups):
    """Places from groups whose area shares a word with `area` (Shinjuku ~ Shinjuku, Kyoto ~ Kyoto Higashiyama)."""
    words = set(area.lower().split())
    return [p for a, places in groups if words & set(a.lower().split()) for p in places]


def polish(facts, draft):
    try:
        return muse.explain(facts, draft)
    except Exception:  # Muse is a nicety here; the facts-only draft is fine
        return draft


# MARK: - Trip files


def budget(r):
    rows, n = [], r.travelers
    sources = []

    def add(label, group, source):
        rows.append([label, money(group / n), money(group), source])
        sources.append(source)

    call, flight = r.flight()
    if flight:
        legs = flight.get("flights", [])
        via = " via " + ", ".join(l["id"] for l in flight.get("layovers", [])) if flight.get("layovers") else ""
        # Google Flights prices cover every adult in the search.
        add(f"Flights · {legs[0]['airline'] if legs else 'best option'}{via}", flight["price"], "Google Flights")
    for s in r.stays():
        add(f"{s['name']} · {s['nights']} nights", s["rate"] * s["nights"] * s["rooms"], "Google Hotels")
    for call, data in r.of("google"):
        price = first_price(data)
        if price:
            label = re.sub(r"\s*\b(fare|price|cost)s?\b", "", call["query"], flags=re.I).strip()
            add(label, price * n, "Google Search")
    start, end = r.trip_dates()
    levels = [PRICE_LEVEL[p["price"]] for _, ps in r.places(food=True) for p in ps if p.get("price") in PRICE_LEVEL]
    if levels and start:
        days = (end - start).days + 1
        add(f"Food · {days} days (from price levels)", sum(levels) / len(levels) * days * n, "Google Maps")
    total = sum(float(row[2].strip("$").replace(",", "")) for row in rows)
    rows.append(["Total", money(total / n), money(total), ""])
    cap = r.plan.get("context", {}).get("budgetPerPerson")
    if cap:
        diff = float(cap) - total / n
        footer = f"{'Under' if diff >= 0 else 'Over'} the {money(float(cap))} budget by {money(abs(diff))} each"
    else:
        footer = f"Per person = group total ÷ {n}"
    content = {"columns": ["Item", "Per person", f"Group of {n}", "Source"], "rows": rows, "footer": footer}
    return content, f"{len(rows) - 1} line items · per person and group totals", sorted(set(sources))


def daily(r):
    start, end = r.trip_dates()
    if not start:
        raise ValueError("Daily needs trip dates: add a flight or hotel search with dates")
    stays = r.stays()
    call, flight = r.flight()
    todo = r.places(food=False)
    food = r.places(food=True)
    members = r.plan.get("members", [])
    blocks = [{"type": "title", "text": f"{r.plan['folderName']} · Daily plan"},
              {"type": "paragraph", "text": " · ".join(filter(None, [f"{day_label(start)} – {day_label(end)}",
                                                                      ", ".join(members)]))}]
    first = stays[0]["area"] if stays else area_of(r.plan["folderName"])
    intro = (f"{(end - start).days + 1} days, {len(stays)} places to stay. "
             "Every stop below comes from a Google search; free days are left open on purpose.")
    blocks.append({"type": "paragraph", "text": polish({"days": (end - start).days + 1, "stays": len(stays)}, intro)})
    area, used = first, set()

    def take(groups):
        for p in near(area, groups):
            if p["title"] not in used:
                used.add(p["title"])
                return p

    for i in range((end - start).days + 1):
        d = start + timedelta(days=i)
        here = next((s for s in stays if s["check_in"] <= d < s["check_out"]), None)
        area = here["area"] if here else area
        items = []
        if d == start and flight:
            leg = flight["flights"][-1]
            items.append(f"{clock(leg['arrival_airport']['time'])}  Land at {leg['arrival_airport']['id']}, "
                         f"{leg['airline']} {leg['flight_number']}")
        for s in stays:
            if s["check_in"] == d:
                items.append(f"Check in at {s['name']}")
        if d == end:
            items.append("Check out and head to the airport for the flight home")
        else:
            if i > 0 and (p := take(todo)):
                items.append(f"See {p['title']}")
            if (p := take(food)):
                items.append(f"Dinner at {p['title']}")
        blocks.append({"type": "heading", "text": f"Day {i + 1} · {d:%a}, {day_label(d)} · {area}"})
        blocks += [{"type": "bullet", "text": t} for t in items or ["Free day: nothing booked yet"]]
    sources = ["Google Flights"] * bool(flight) + ["Google Hotels"] * bool(stays) + ["Google Maps"] * bool(todo or food)
    return {"blocks": blocks}, f"{(end - start).days + 1} days · day-by-day plan", sources


def place_line(p):
    return " · ".join(str(x) for x in [p["title"], p.get("rating"), p.get("type"), p.get("price")] if x)


def stay_and_food(r):
    stays = r.stays()
    blocks = [{"type": "title", "text": "Places to stay + food"}, {"type": "heading", "text": "Staying"}]
    blocks += [{"type": "bullet", "text": f"{s['name']} · {s['rating']} · {money(s['rate'])} a night per room · "
                                         f"{day_label(s['check_in'])} – {day_label(s['check_out'])}"} for s in stays]
    for area, places in r.places(food=True):
        blocks.append({"type": "heading", "text": f"Eating near {area}"})
        blocks += [{"type": "bullet", "text": place_line(p)} for p in places[:5]]
    count = sum(len(ps[:5]) for _, ps in r.places(food=True))
    return {"blocks": blocks}, f"{len(stays)} stays · {count} places to eat", ["Google Hotels", "Google Maps"]


# MARK: - Car files

SIMULATED = "Simulated account data: the buyout price and votes are demo numbers, not from a real lease."


def listings(r):
    out = []
    for _, data in r.of("google_shopping"):
        for item in data.get("shopping_results", []):
            if item.get("extracted_price"):
                miles = re.search(r"([\d,]{4,})\s*mi", item["title"] + " " + item.get("snippet", ""))
                out.append({"title": item["title"], "price": item["extracted_price"], "source": item.get("source", ""),
                            "miles": int(miles.group(1).replace(",", "")) if miles else None})
    return out


def market_prices(r):
    items = listings(r)
    if not items:
        raise ValueError("Market prices needs a Google Shopping search with priced listings")
    avg = sum(i["price"] for i in items) / len(items)
    rows = [[i["title"], f"{i['miles']:,}" if i["miles"] else "", money(i["price"]), i["source"]] for i in items[:10]]
    rows.append([f"Average of {len(items)}", "", money(avg), ""])
    buyout = r.plan.get("context", {}).get("buyoutPrice")
    footer = f"Your buyout price: {money(float(buyout))} · {SIMULATED}" if buyout else SIMULATED
    content = {"columns": ["Listing", "Miles", "Price", "Seller"], "rows": rows, "footer": footer}
    return content, f"{len(items)} similar cars for sale", ["Google Shopping"]


def dealer_prep(r):
    blocks = [{"type": "title", "text": "Dealer visit"}, {"type": "heading", "text": "Bring"},
              {"type": "bullet", "text": "Driver's license and proof of insurance"},
              {"type": "bullet", "text": "Lease agreement and latest statement"}]
    dealers = [p for _, data in r.of("google_maps") for p in data.get("local_results", [])][:4]
    if dealers:
        blocks.append({"type": "heading", "text": "Dealers nearby"})
        blocks += [{"type": "bullet", "text": " · ".join(str(x) for x in [p["title"], p.get("rating"), p.get("address"),
                                                                         p.get("phone")] if x)} for p in dealers]
    ask = []
    rate = next(filter(None, (first_rate(d) for _, d in r.of("google"))), None)
    if rate:
        ask.append(f"Can you match {rate}% APR?")
    buyout = r.plan.get("context", {}).get("buyoutPrice")
    ask.append(f"Any fees on top of the {money(float(buyout))} buyout?" if buyout else "Any fees on top of the buyout?")
    ask.append("Is a pre-purchase inspection included?")
    blocks.append({"type": "heading", "text": "Ask"})
    blocks += [{"type": "bullet", "text": t} for t in ask]
    offers = [o for call, d in r.of("google") if "lease" in call["query"].lower() for o in d.get("organic_results", [])]
    if offers:
        blocks.append({"type": "heading", "text": "Current offers to mention"})
        blocks += [{"type": "bullet", "text": f"{o['title']} · {o['link']}"} for o in offers[:3]]
    blocks.append({"type": "paragraph", "text": SIMULATED})
    return {"blocks": blocks}, f"What to bring and ask · {len(dealers)} dealers", ["Google Maps", "Google Search"]


def decision_summary(r):
    ctx = r.plan.get("context", {})
    items = listings(r)
    facts = {"listings": len(items)}
    draft = []
    if items:
        facts["average_price"] = round(sum(i["price"] for i in items) / len(items))
        draft.append(f"Similar cars sell for about {money(facts['average_price'])} across {len(items)} listings.")
    if ctx.get("buyoutPrice"):
        facts["buyout_price"] = float(ctx["buyoutPrice"])
        if items:
            gap = facts["average_price"] - facts["buyout_price"]
            draft.append(f"The buyout price of {money(facts['buyout_price'])} is about {money(abs(gap))} "
                         f"{'under' if gap >= 0 else 'over'} that.")
    if ctx.get("votes"):
        facts["votes"] = ctx["votes"]
        draft.append(ctx["votes"])
    title = f"{r.plan['folderName']}: {ctx['decision']}" if ctx.get("decision") else f"{r.plan['folderName']}: decision"
    blocks = [{"type": "title", "text": title},
              {"type": "paragraph", "text": polish(facts, " ".join(draft) or "Not enough listings to compare yet.")},
              {"type": "paragraph", "text": SIMULATED}]
    return {"blocks": blocks}, "Why the group chose it", ["Google Shopping"]


WRITERS = {"budget tracker": budget, "daily": daily, "places to stay + food": stay_and_food,
           "market prices": market_prices, "dealer visit prep": dealer_prep, "decision summary": decision_summary}


def write(file, research):
    """(content, summary, sources) for one file: researched if we know it, else what the app sent."""
    writer = WRITERS.get(file["name"].lower())
    if writer:
        return writer(research)
    content = file.get("content") or {"blocks": [{"type": "title", "text": file["name"]}]}
    return content, file.get("summary") or "", file.get("sources") or []


# MARK: - Build


def run(b, plan, make_drive, pace=None, on_done=None):
    drive, folder = None, None
    try:
        drive = make_drive()
        pace = PACE if pace is None and getattr(drive, "mock", False) else (pace or 0)
        results, calls = {}, []
        for call in plan["calls"]:
            b.check()
            b.emit("researching", id=call["id"], engine=call["engine"], query=call["query"])
            t = time.monotonic()
            results[call["id"]] = data = serp.search(call["engine"], **search_params(call, plan))
            time.sleep(pace)
            done = {"id": call["id"], "result": count_label(call["engine"], data),
                    "duration": round(time.monotonic() - t, 1)}
            calls.append({**done, "engine": call["engine"], "query": call["query"]})
            b.emit("researched", **done)
        research = Research(plan, results)
        b.check()
        folder = drive.create_folder(plan["folderName"])
        files = []
        for f in plan["files"]:
            b.check()
            b.emit("writing", id=f["id"], name=f["name"], kind=f["kind"])
            content, summary, sources = write(f, research)
            if f["kind"] == "sheet":
                url = drive.create_sheet(folder, f["name"], content["columns"], content["rows"], content.get("footer"))
            else:
                url = drive.create_doc(folder, f["name"], content["blocks"])
            time.sleep(pace)
            files.append({"id": f["id"], "name": f["name"], "kind": f["kind"], "summary": summary,
                          "sources": sources, "url": url, "content": content})
            b.emit("wrote", id=f["id"], summary=summary)
        b.check()
        b.emit("finished", folderName=plan["folderName"], url=drive.share(folder), files=files, calls=calls,
               mock=getattr(drive, "mock", False))
        if on_done:
            try:
                on_done(plan, files)
            except Exception:
                pass  # bookkeeping only; the folder is already built
    except Exception as e:
        if folder:  # never leave a half-built folder behind
            try:
                drive.delete(folder)
            except Exception:
                pass
        if isinstance(e, Cancelled):
            b.emit("cancelled")
        else:
            b.emit("failed", message=str(e) or type(e).__name__)
    finally:
        b.done = True
