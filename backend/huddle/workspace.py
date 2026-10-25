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


# Muse sometimes writes a city instead of an airport code ("AUS → Tokyo"). These cover the cities groups ask about most.
AIRPORTS = {
    "tokyo": "HND", "osaka": "KIX", "kyoto": "KIX", "seoul": "ICN", "london": "LHR", "paris": "CDG", "rome": "FCO",
    "barcelona": "BCN", "madrid": "MAD", "lisbon": "LIS", "amsterdam": "AMS", "dublin": "DUB", "mexico city": "MEX",
    "cancun": "CUN", "cancún": "CUN", "toronto": "YYZ", "montreal": "YUL", "vancouver": "YVR", "honolulu": "HNL",
    "austin": "AUS", "dallas": "DFW", "houston": "IAH", "chicago": "ORD", "new york": "JFK", "nyc": "JFK",
    "boston": "BOS", "seattle": "SEA", "phoenix": "PHX", "denver": "DEN", "atlanta": "ATL", "nashville": "BNA",
    "los angeles": "LAX", "la": "LAX", "san francisco": "SFO", "miami": "MIA", "orlando": "MCO", "las vegas": "LAS",
    "washington": "IAD", "dc": "IAD", "philadelphia": "PHL", "san diego": "SAN", "portland": "PDX",
}


def airport(name):
    """'AUS' stays 'AUS'; a known city becomes its main airport; anything else is None."""
    name = name.strip().strip(".")
    if re.fullmatch(r"[A-Z]{3}", name):
        return name
    return AIRPORTS.get(name.lower())


def flight_route(query):
    m = re.match(r"\s*([A-Za-zÀ-ÿ .]+?)\s*(?:→|->|\bto\b)\s*([A-Za-zÀ-ÿ .]+?)\s*(?:,|$)", query)
    if not m:
        return None
    a, b = airport(m[1]), airport(m[2])
    return (a, b) if a and b else None


class Unsearchable(ValueError):
    """A search Muse planned that we can't run as written; the build skips it instead of failing."""


def search_params(call, plan):
    q, engine, year = call["query"], call["engine"], plan_year(plan)
    if engine == "google_flights":
        route = flight_route(q)
        dates = date_range(q, year)
        if not (route and dates):
            raise Unsearchable(f"Skipped the flight search \"{q}\": it needs two airports and dates.")
        params = {"departure_id": route[0], "arrival_id": route[1], "outbound_date": dates[0].isoformat(),
                  "return_date": dates[1].isoformat(), "adults": _number(r"(\d+)\s*adults?", q, 1),
                  "currency": "USD", "hl": "en"}
    elif engine == "google_hotels":
        dates = date_range(q, year)
        if not dates:
            raise Unsearchable(f"Skipped the hotel search \"{q}\": it needs dates.")
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


def builds_use_muse():
    """Folder builds skip Muse until this is turned back on. See docs/RESTORE_MUSE.md."""
    return os.environ.get("MUSE_ENABLED") == "1" and bool(os.environ.get("MODEL_API_KEY"))


def polish(facts, draft):
    if not builds_use_muse():
        return draft
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
        # A web snippet's "$" is only trustworthy when the search was for a fare or a ticket price.
        if not re.search(r"\b(fare|ticket|pass|admission|entry|price|cost)s?\b", call["query"], re.I):
            continue
        price = first_price(data)
        if price:
            label = re.sub(r"\s*\b(fare|price|cost)s?\b", "", call["query"], flags=re.I).strip()
            add(label, price * n, "Google Search")
    start, end = r.trip_dates()
    levels = [PRICE_LEVEL[p["price"]] for _, ps in r.places(food=True) for p in ps if p.get("price") in PRICE_LEVEL]
    if levels and start:
        days = (end - start).days + 1
        add(f"Food · {days} days (from price levels)", sum(levels) / len(levels) * days * n, "Google Maps")
    cap = r.plan.get("context", {}).get("budgetPerPerson")
    if not rows:
        if not cap:
            raise ValueError("There are no prices to budget yet.")
        # Nothing priced in the searches: show what the group said they'd spend, labeled as such.
        add("Planned spend (from the chat)", float(cap) * n, "Plan")
    total = sum(float(row[2].strip("$").replace(",", "")) for row in rows)
    rows.append(["Total", money(total / n), money(total), ""])
    if cap:
        diff = float(cap) - total / n
        if abs(diff) < 0.5:
            footer = f"Right on the {money(float(cap))} budget"
        else:
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
    """Priced cars. Shopping rarely lists used cars, so a 'for sale' web search counts too."""
    out = []

    def add(title, price, source, blob):
        if not price or price < 1000:
            return
        miles = re.search(r"([\d,]{4,})\s*mi", blob)
        out.append({"title": title, "price": price, "source": source,
                    "miles": int(miles.group(1).replace(",", "")) if miles else None})

    for _, data in r.of("google_shopping"):
        for item in data.get("shopping_results", []):
            add(item.get("title") or "Listing", item.get("extracted_price"), item.get("source", ""),
                item.get("title", "") + " " + item.get("snippet", ""))
    for call, data in r.of("google"):
        if "for sale" not in call["query"].lower():
            continue
        for item in data.get("organic_results", []):
            add(item.get("title") or "Listing", first_price({"organic_results": [item]}), "Google Search",
                item.get("title", "") + " " + item.get("snippet", ""))
    return out


def market_prices(r):
    items = listings(r)
    if not items:
        raise ValueError("Market prices needs a Google Shopping search with priced listings")
    avg = sum(i["price"] for i in items) / len(items)
    rows = [[i["title"], f"{i['miles']:,}" if i["miles"] else "", money(i["price"]), i["source"]] for i in items[:10]]
    rows.append([f"Average of {len(items)}", "", money(avg), ""])
    buyout = r.plan.get("context", {}).get("buyoutPrice")
    simulated = bool(buyout) or r.plan.get("context", {}).get("simulated")
    if buyout and simulated:
        footer = f"Your buyout price: {money(float(buyout))} · {SIMULATED}"
    elif buyout:
        footer = f"Your buyout price: {money(float(buyout))}"
    else:
        footer = SIMULATED if simulated else None
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
    if r.plan.get("context", {}).get("buyoutPrice") or r.plan.get("context", {}).get("simulated"):
        blocks.append({"type": "paragraph", "text": SIMULATED})
    return {"blocks": blocks}, f"What to bring and ask · {len(dealers)} dealers", ["Google Maps", "Google Search"]


def decision_summary(r):
    ctx = r.plan.get("context", {})
    notes = " ".join(filter(None, [r.plan.get("notes", ""), *r.plan.get("messages", [])]))
    items = listings(r)
    facts = {"listings": len(items)}
    draft = []
    buyout = ctx.get("buyoutPrice")
    if not buyout and (m := re.search(r"buy\s*-?out\D{0,20}\$\s?([\d,]+)", notes, re.I)):
        buyout = m.group(1).replace(",", "")
    if items:
        facts["average_price"] = round(sum(i["price"] for i in items) / len(items))
        draft.append(f"Similar cars sell for about {money(facts['average_price'])} across {len(items)} listings.")
    if buyout:
        facts["buyout_price"] = float(buyout)
        if items:
            gap = facts["average_price"] - facts["buyout_price"]
            draft.append(f"The buyout price of {money(facts['buyout_price'])} is about {money(abs(gap))} "
                         f"{'under' if gap >= 0 else 'over'} that.")
        else:
            draft.append(f"The buyout price is {money(facts['buyout_price'])}. No similar listings were found to compare it with yet.")
    if ctx.get("votes"):
        facts["votes"] = ctx["votes"]
        draft.append(ctx["votes"])
    if not draft and notes:
        facts["notes"] = notes[:600]
        draft.append(f"What the group said: {notes[:300]}")
    title = f"{r.plan['folderName']}: {ctx['decision']}" if ctx.get("decision") else r.plan["folderName"]
    blocks = [{"type": "title", "text": title},
              {"type": "paragraph", "text": polish(facts, " ".join(draft) or "Not enough listings to compare yet.")}]
    if ctx.get("buyoutPrice") or ctx.get("simulated"):
        blocks.append({"type": "paragraph", "text": SIMULATED})
    return {"blocks": blocks}, "Where the decision stands", ["Google Shopping"] if items else ["Plan"]


def comparison(r):
    rows = []
    for o in r.plan.get("options") or []:
        if not isinstance(o, dict):
            continue
        votes = o.get("votes")
        if isinstance(votes, list):
            votes = len(votes)
        rows.append([o.get("title") or "Option", str(o.get("monthly") or o.get("price") or ""),
                     str(o.get("total") or ""), "" if votes is None else str(votes)])
    if not rows:
        rows = [[i["title"], "", money(i["price"]), ""] for i in listings(r)[:6]]
    if not rows:
        raise ValueError("Cost comparison needs options or priced listings")
    footer = SIMULATED if r.plan.get("context", {}).get("buyoutPrice") or r.plan.get("context", {}).get("simulated") else None
    content = {"columns": ["Option", "Monthly", "Total", "Votes"], "rows": rows, "footer": footer}
    return content, f"{len(rows)} options", ["Plan"]


def showtimes(r):
    rows = []
    for _, data in r.of("google"):
        for item in data.get("organic_results", [])[:8]:
            price = first_price({"organic_results": [item]})
            rows.append([item.get("title") or "Show", (item.get("snippet") or "")[:90],
                         money(price) if price else "", "Google Search"])
    for _, data in r.of("google_maps"):
        for p in data.get("local_results", [])[:6]:
            if any(w in (p.get("type") or "").lower() for w in ("restaurant", "food")):
                continue
            rows.append([p.get("title") or "Theater", p.get("address") or "", p.get("price") or "", "Google Maps"])
    if not rows:
        raise ValueError("Showtimes needs a search with theaters or listings")
    content = {"columns": ["Show", "Detail", "Price", "Source"], "rows": rows, "footer": None}
    return content, f"{len(rows)} showtimes", ["Google Search", "Google Maps"]


def evening(r):
    movie = any(w in plan_blob(r.plan) for w in ("movie", "film", "showtime", "cinema", "theater", "theatre"))
    blocks = [{"type": "title", "text": f"{r.plan['folderName']} · Evening"},
              {"type": "heading", "text": "The movie" if movie else "Where to go"}]
    for _, data in r.of("google"):
        blocks += [{"type": "bullet", "text": f"{item.get('title', '')} · {(item.get('snippet') or '')[:100]}"}
                   for item in data.get("organic_results", [])[:5]]
    food = r.places(food=True)
    if food:
        blocks.append({"type": "heading", "text": "Food nearby"})
        for area, places in food:
            blocks += [{"type": "bullet", "text": place_line(p)} for p in places[:4]]
    if len(blocks) == 2:
        blocks.append({"type": "paragraph", "text": r.plan.get("notes") or "No showtimes in the search yet."})
    return {"blocks": blocks}, "Evening plan", ["Google Search", "Google Maps"]


def outing_doc(r):
    blocks = [{"type": "title", "text": r.plan["folderName"]}, {"type": "heading", "text": "Where"}]
    seen = set()
    for _, data in r.of("google_maps"):
        for p in data.get("local_results", [])[:6]:
            if p.get("title") in seen:
                continue
            seen.add(p.get("title"))
            blocks.append({"type": "bullet", "text": place_line(p)})
    if r.plan.get("notes"):
        blocks.append({"type": "paragraph", "text": r.plan["notes"]})
    if len(blocks) == 2:
        blocks.append({"type": "paragraph", "text": "Nothing booked yet."})
    return {"blocks": blocks}, f"{max(len(seen), 0)} places", ["Google Maps"]


def shopping_sheet(r):
    rows = []
    for o in r.plan.get("options") or []:
        if isinstance(o, dict) and o.get("title"):
            rows.append([o["title"], o.get("detail") or "", str(o.get("price") or ""), o.get("source") or "Plan"])
    for _, data in r.of("google_shopping"):
        for item in data.get("shopping_results", [])[:8]:
            rows.append([item.get("title") or "Item", "", item.get("price") or "", item.get("source") or "Google Shopping"])
    if not rows:
        raise ValueError("Shopping list needs items or shopping results")
    content = {"columns": ["Item", "Detail", "Price", "Source"], "rows": rows, "footer": None}
    return content, f"{len(rows)} items", ["Google Shopping", "Plan"]


def overview(r):
    blocks = [{"type": "title", "text": r.plan["folderName"]}]
    if r.plan.get("notes"):
        blocks.append({"type": "paragraph", "text": r.plan["notes"]})
    blocks.append({"type": "heading", "text": "What we found"})
    found = 0
    for _, data in r.of("google"):
        for item in data.get("organic_results", [])[:6]:
            found += 1
            blocks.append({"type": "bullet", "text": f"{item.get('title', '')} · {item.get('link', '')}"})
    for d in r.plan.get("decisions") or []:
        if isinstance(d, dict) and d.get("title"):
            blocks.append({"type": "bullet", "text": f"{d['title']}: {d.get('choice') or d.get('value') or ''}".rstrip(": ")})
    return {"blocks": blocks}, f"{found} sources" if found else "Plan overview", ["Google Search"]


ROLES = {
    "budget": ("sheet", "Budget"),
    "daily": ("doc", "Daily"),
    "places": ("doc", "Places to stay + food"),
    "comparison": ("sheet", "Cost comparison"),
    "market": ("sheet", "Market prices"),
    "dealer": ("doc", "Dealer visit prep"),
    "decision": ("doc", "Decision summary"),
    "showtimes": ("sheet", "Showtimes"),
    "evening": ("doc", "Evening plan"),
    "outing": ("doc", "Plan"),
    "shopping": ("sheet", "Shopping list"),
    "overview": ("doc", "Overview"),
}
ENGINES = {"google", "google_flights", "google_hotels", "google_maps", "google_shopping"}
ROLE_WRITERS = {"budget": budget, "daily": daily, "places": stay_and_food, "comparison": comparison,
                "market": market_prices, "dealer": dealer_prep, "decision": decision_summary,
                "showtimes": showtimes, "evening": evening, "outing": outing_doc,
                "shopping": shopping_sheet, "overview": overview}
WRITERS = {"budget tracker": budget, "daily": daily, "places to stay + food": stay_and_food,
           "market prices": market_prices, "dealer visit prep": dealer_prep, "decision summary": decision_summary}


def plan_blob(plan):
    parts = [plan.get("folderName") or "", plan.get("name") or "", plan.get("notes") or "", plan.get("kind") or ""]
    parts += [str(m) for m in plan.get("messages") or []]
    for d in plan.get("decisions") or []:
        if isinstance(d, dict):
            parts.append(f"{d.get('title', '')} {d.get('choice') or d.get('value') or ''}")
    for o in plan.get("options") or []:
        if isinstance(o, dict):
            parts.append(" ".join(str(o.get(k) or "") for k in ("title", "detail", "category", "price")))
    parts += [f"{k} {v}" for k, v in (plan.get("context") or {}).items()]
    for day in plan.get("itinerary") or []:
        if isinstance(day, dict):
            parts.append(f"{day.get('date') or ''} {day.get('city') or ''}")
            for slot in day.get("slots") or []:
                if isinstance(slot, dict):
                    parts.append(" ".join(str(slot.get(k) or "") for k in ("time", "title", "detail")))
    return " ".join(parts)


def plan_name(plan):
    return plan.get("folderName") or plan.get("name") or "Plan"


def classify(plan):
    """Which pack of files this plan is. Movie is checked before trip so a movie night never gets flights."""
    low, kind = plan_blob(plan).lower(), (plan.get("kind") or "").lower()
    def word(w):
        return re.search(rf"\b{re.escape(w)}\b", low) is not None
    if kind == "movie" or any(word(w) for w in ("movie", "theater", "theatre", "cinema", "showtimes", "showtime")):
        return "movie"
    if kind in {"shopping", "shop"} or any(word(w) for w in ("grocery", "groceries")) or "shopping list" in low:
        return "shopping"
    if kind in {"car", "lease"} or any(word(w) for w in ("rav4", "lease", "buyout", "dealer", "toyota")):
        return "car"
    if kind == "decision" and any(word(w) for w in ("car", "suv", "lease")):
        return "car"
    if kind in {"trip", "travel"} or any(word(w) for w in ("flight", "flights", "hotel", "itinerary", "airport")):
        return "trip"
    if kind == "outing" or any(word(w) for w in ("hike", "outing", "picnic", "trail")):
        return "outing"
    return "other"


def flight_query(plan):
    text = plan_blob(plan)
    dates = DATES.search(text)
    adults = max(len(plan.get("members") or []), 1)
    pair = re.search(r"([A-Z]{3})\s*(?:→|->|to)\s*([A-Z]{3})", text)
    if pair and dates:
        return f"{pair.group(1)} → {pair.group(2)}, {dates.group(0)}, {adults} adults"
    low = text.lower()
    if dates and "austin" in low and any(w in low for w in ("japan", "tokyo", "hnd")):
        return f"AUS → HND, {dates.group(0)}, {adults} adults"
    return None


def heuristic_outputs(plan):
    """Offline stand-in for Muse's select_outputs. Same roles the live model is allowed to pick."""
    kind, text, low = classify(plan), plan_blob(plan), plan_blob(plan).lower()
    name = plan_name(plan)
    dates = DATES.search(text)
    span = dates.group(0) if dates else None

    def call(engine, query):
        return {"engine": engine, "query": query}

    def file(role, title=None):
        kind_name, default = ROLES[role]
        return {"role": role, "name": title or default, "kind": kind_name}

    if kind == "movie":
        return {"calls": [call("google", f"{name} showtimes theater"), call("google_maps", f"restaurants near {name}")],
                "files": [file("showtimes"), file("evening")]}
    if kind == "shopping":
        return {"calls": [call("google_shopping", name)], "files": [file("shopping")]}
    if kind == "car":
        loc = (plan.get("context") or {}).get("location") or ("Austin" if "austin" in low else "")
        place = " ".join(loc.replace(",", " ").split())
        vehicle = (plan.get("context") or {}).get("vehicle") or "2023 Toyota RAV4 XLE"
        # Google Shopping does not return used-car listings. Prices come from a for-sale web search.
        calls = [call("google", f"{vehicle} for sale {place}".strip()),
                 call("google", "auto loan rates for a lease buyout" if any(w in low for w in ("lease", "buyout")) else f"{vehicle} reviews"),
                 call("google_maps", f"dealers near {place or 'me'}")]
        files = [file("comparison"), file("market"), file("decision")]
        if "dealer" in low:
            files.append(file("dealer"))
        return {"calls": calls, "files": files}
    if kind == "trip":
        calls, cities = [], [label for key, label in (("shinjuku", "Shinjuku"), ("kyoto", "Kyoto"), ("tokyo", "Tokyo")) if key in low]
        fq = flight_query(plan)
        if fq:
            calls.append(call("google_flights", fq))
        if span and cities:
            calls.append(call("google_hotels", f"{cities[0]}, {span}, 2 rooms"))
            calls.append(call("google_maps", f"best food, {cities[0]}"))
            calls.append(call("google_maps", f"top things to do, {cities[-1]}"))
            if len(cities) > 1:
                calls.append(call("google", f"train {cities[0]} to {cities[-1]} fare"))
        if not calls:
            calls.append(call("google", f"{name} travel"))
        files = []
        engines = {c["engine"] for c in calls}
        if engines & {"google_flights", "google_hotels", "google"}:
            files.append(file("budget", "Budget Tracker"))
        if engines & {"google_flights", "google_hotels"}:
            files += [file("daily"), file("places")]
        return {"calls": calls, "files": files or [file("overview")]}
    if kind == "outing":
        files = [file("outing")]
        if "$" in text:
            files.append(file("budget"))
        return {"calls": [call("google_maps", name), call("google_maps", f"food near {name}")], "files": files}
    return {"calls": [call("google", name)], "files": [file("overview")]}


def _keep_role(role, calls, plan):
    engines = {c["engine"] for c in calls}
    if role == "daily":
        return bool(engines & {"google_flights", "google_hotels"})
    if role == "budget":
        return bool(engines & {"google_flights", "google_hotels", "google_shopping"}) or "$" in plan_blob(plan)
    if role == "market":
        return "google_shopping" in engines or any("for sale" in (c.get("query") or "").lower() for c in calls)
    if role in {"shopping", "comparison"}:
        return "google_shopping" in engines or bool(plan.get("options"))
    if role == "showtimes":
        return bool(engines & {"google", "google_maps"})
    if role == "places":
        return bool(engines & {"google_hotels", "google_maps"})
    return True


def choose_outputs(plan):
    """Pick searches and files, then drop anything this plan cannot fill. Empty means the build fails.

    With Muse off, the local chooser in heuristic_outputs decides. See docs/RESTORE_MUSE.md.
    """
    raw = muse.select_outputs(plan) if builds_use_muse() else heuristic_outputs(plan)
    calls = []
    for c in raw.get("calls") or []:
        engine, query = c.get("engine"), (c.get("query") or "").strip()
        if engine not in ENGINES or not query:
            continue
        params = {str(k): str(v) for k, v in (c.get("params") or {}).items() if v is not None}
        calls.append({"id": str(uuid.uuid4()), "engine": engine, "query": query, "params": params})
    files = []
    for f in raw.get("files") or []:
        role = f.get("role")
        if role not in ROLES or not _keep_role(role, calls, plan):
            continue
        kind, default = ROLES[role]
        files.append({"id": str(uuid.uuid4()), "name": (f.get("name") or default)[:80], "kind": kind, "role": role})
    if not calls:
        calls.append({"id": str(uuid.uuid4()), "engine": "google", "query": plan_name(plan), "params": {}})
        files = [f for f in files if _keep_role(f["role"], calls, plan)]
    if not files:
        raise ValueError("Muse did not choose any files this plan can fill")
    return {"calls": calls, "files": files}


def prepare(plan):
    plan = dict(plan)
    plan["folderName"] = plan_name(plan)
    if plan.get("calls") and plan.get("files"):
        return plan
    chosen = choose_outputs(plan)
    plan["calls"], plan["files"] = chosen["calls"], chosen["files"]
    return plan


def write(file, research):
    """(content, summary, sources) for one file: researched if we know it, else what the app sent."""
    writer = ROLE_WRITERS.get(file.get("role")) or WRITERS.get(file["name"].lower())
    if writer:
        return writer(research)
    content = file.get("content") or {"blocks": [{"type": "title", "text": file["name"]}]}
    return content, file.get("summary") or "", file.get("sources") or []


# MARK: - Build


def run(b, plan, make_drive, pace=None, on_done=None):
    drive, folder = None, None
    try:
        plan = prepare(plan)
        b.emit("planned", folderName=plan["folderName"],
               calls=[{"id": c["id"], "engine": c["engine"], "query": c["query"]} for c in plan["calls"]],
               files=[{"id": f["id"], "name": f["name"], "kind": f["kind"]} for f in plan["files"]])
        drive = make_drive()
        pace = PACE if pace is None and getattr(drive, "mock", False) else (pace or 0)
        results, calls = {}, []
        for call in plan["calls"]:
            b.check()
            b.emit("researching", id=call["id"], engine=call["engine"], query=call["query"])
            t = time.monotonic()
            try:
                params = search_params(call, plan)
            except Unsearchable as e:
                results[call["id"]] = {}
                done = {"id": call["id"], "result": str(e), "duration": 0}
                calls.append({**done, "engine": call["engine"], "query": call["query"]})
                b.emit("researched", **done)
                continue
            results[call["id"]] = data = serp.search(call["engine"], **params)
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
            try:
                content, summary, sources = write(f, research)
            except ValueError as e:
                # One file the searches can't fill shouldn't sink the folder; say so and keep going.
                b.emit("wrote", id=f["id"], summary=f"Skipped: {e}")
                continue
            if f["kind"] == "sheet":
                url = drive.create_sheet(folder, f["name"], content["columns"], content["rows"], content.get("footer"))
            else:
                url = drive.create_doc(folder, f["name"], content["blocks"])
            time.sleep(pace)
            files.append({"id": f["id"], "name": f["name"], "kind": f["kind"], "summary": summary,
                          "sources": sources, "url": url, "content": content})
            b.emit("wrote", id=f["id"], summary=summary)
        b.check()
        if not files:
            raise ValueError("Couldn't fill any files for this plan yet. Add dates, places, or a budget in the chat and try again.")
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
