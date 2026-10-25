"""The tabs on a plan. Muse may replace this; these rules are the fallback and the safety check."""
import re

KINDS = {"overview", "options", "people", "money", "tasks", "route", "decision"}
# Older replies named a fixed tab. New ones name the tab for this plan.
LEGACY = {
    "overview": ("overview", "Overview", "overview"),
    "flights": ("flights", "Flights", "options"),
    "stays": ("stays", "Stays", "options"),
    "places": ("places", "Places", "options"),
    "todo": ("todo", "Do", "tasks"),
    "guests": ("guests", "Who's in", "people"),
    "money": ("money", "Money", "money"),
    "route": ("route", "Route", "route"),
    "gettingThere": ("gettingThere", "Getting there", "route"),
    "options": ("options", "Options", "decision"),
    "numbers": ("numbers", "Numbers", "decision"),
    "prices": ("prices", "Prices", "decision"),
}


def infer(name="", kind="", request="", notes=""):
    """Tabs that match the plan in front of us. A movie night is not a flight search."""
    text = f"{name} {request} {notes}".lower()
    if kind == "decision" or _has(text, ("lease", "buyout", "buy out", "car deal")):
        style = "purchase"
    elif _has(text, ("movie", "showtime", "theater", "theatre")):
        style = "event"
    elif _has(text, ("dinner", "lunch", "brunch", "restaurant")) and not _has(text, ("trip", "weekend", "flight")):
        style = "dinner"
    elif _has(text, ("birthday", "bachelorette", "party", "wedding", "concert")) and not _has(text, ("flight", "fly")):
        style = "event"
    elif _has(text, ("road trip", "drive", "driving")):
        style = "roadTrip"
    elif _has(text, ("train", "bus", "amtrak")):
        style = "groundTrip"
    elif kind in ("gathering", "general") and not _has(text, ("flight", "fly", "trip")):
        style = "event"
    else:
        style = "flightTrip"
    budget = _budget(text)
    people = _first_int(r"(\d+)\s*(?:of us|people|adults|friends)", text)
    chips = _chips(name, request, notes, style, people, budget)
    tabs = _tabs_for(style, text, budget, people)
    return {"style": style, "tabs": tabs, "chips": chips, "people": people, "budget": budget}


def _tabs_for(style, text, budget, people):
    """How many tabs, and what they're called, follows the plan. A movie night is not Who's in plus Do."""
    if style == "purchase":
        tabs = [_tab("options", "Options", "decision"), _tab("numbers", "Numbers", "decision"), _tab("prices", "Prices", "decision")]
    elif _has(text, ("movie", "showtime", "theater", "theatre")):
        tabs = [_tab("theaters", "Theaters", "options")]
        if _has(text, ("eat", "food", "dinner", "restaurant")):
            tabs.append(_tab("food", "Food", "options"))
    elif style == "dinner":
        tabs = [_tab("places", "Places", "options")]
        if people:
            tabs.append(_tab("guests", "Who's in", "people"))
    elif style == "roadTrip":
        tabs = [_tab("route", "Route", "route"), _tab("stays", "Stays", "options"), _tab("todo", "Do", "tasks")]
    elif style == "groundTrip":
        tabs = [_tab("gettingThere", "Getting there", "route"), _tab("stays", "Stays", "options"), _tab("todo", "Do", "tasks")]
    elif style == "event":
        tabs = [_tab("places", "Places", "options")]
        if people:
            tabs.append(_tab("guests", "Who's in", "people"))
    else:
        tabs = [_tab("flights", "Flights", "options"), _tab("stays", "Stays", "options"), _tab("todo", "Do", "tasks")]
    if budget and style not in ("purchase", "dinner"):
        tabs.append(_tab("money", "Money", "money"))
    return [_tab("overview", "Overview", "overview")] + tabs[:4]


def finalize(raw, facts):
    """Keep Muse's tabs when they fit this plan. Drop anything the plan never said."""
    base = infer(facts.get("name", ""), facts.get("kind", ""), facts.get("request", ""), facts.get("notes", ""))
    if not raw:
        return base
    source = f"{facts.get('name', '')} {facts.get('request', '')} {facts.get('notes', '')}"
    style = raw.get("style") if raw.get("style") in ("flightTrip", "roadTrip", "groundTrip", "dinner", "event", "purchase") else base["style"]
    tabs = []
    for item in raw.get("tabs") or []:
        tab = _normalize(item)
        if tab and tab["id"] not in {t["id"] for t in tabs}:
            tabs.append(tab)
    if not tabs:
        tabs = list(base["tabs"])
    tabs = [tab for tab in tabs if tab["id"] != "overview"]
    tabs.insert(0, _tab("overview", "Overview", "overview"))
    budget = raw.get("budget") if isinstance(raw.get("budget"), str) and raw["budget"].lower() in source.lower() else base["budget"]
    if not budget:
        tabs = [tab for tab in tabs if tab["kind"] != "money"]
    chips = [chip.strip() for chip in (raw.get("chips") or [])
             if isinstance(chip, str) and chip.strip() and _grounded(chip, source)]
    people = raw.get("people") if isinstance(raw.get("people"), int) else base["people"]
    return {"style": style, "tabs": tabs[:5], "chips": (chips or base["chips"])[:6], "people": people, "budget": budget}


def _tab(tab_id, title, kind):
    return {"id": tab_id, "title": title, "kind": kind}


def _normalize(item):
    if isinstance(item, str):
        legacy = LEGACY.get(item)
        return _tab(*legacy) if legacy else None
    if not isinstance(item, dict):
        return None
    kind = item.get("kind")
    if kind not in KINDS:
        legacy = LEGACY.get(item.get("id") or "")
        return _tab(*legacy) if legacy else None
    title = str(item.get("title") or "").strip()[:24]
    tab_id = re.sub(r"[^a-z0-9]+", "", str(item.get("id") or title).lower())[:24]
    if not tab_id or not title:
        return None
    return _tab(tab_id, title, kind)


def _chips(name, request, notes, style, people, budget):
    blob = f"{name} {request} {notes}"
    text = blob.lower()
    chips = []
    if style == "flightTrip":
        origin = _first(r"from ([A-Z][a-zA-Z]+)", blob)
        if origin:
            chips.append(f"Flying from {origin}")
    if style == "roadTrip":
        chips.append("Driving")
    if style == "groundTrip":
        chips.append("Train or bus")
    if people:
        chips.append(f"{people} people")
    if budget:
        chips.append(budget)
    if _has(text, ("vegan",)):
        chips.append("Vegan option")
    if _has(text, ("vegetarian",)):
        chips.append("Vegetarian option")
    if _has(text, ("wheelchair", "accessible")):
        chips.append("Step-free only")
    near = _first(r"near ([A-Z][a-zA-Z]+)", blob)
    if near:
        chips.append(f"Near {near}")
    return chips


def _budget(text):
    found = _first(r"(\$[\d,]+)\s*(?:each|pp|per person|a person)", text)
    return f"{found} each" if found else None


def _has(text, words):
    return any(re.search(rf"\b{re.escape(word)}\b", text) for word in words)


def _first(pattern, text):
    match = re.search(pattern, text)
    return match.group(1) if match else None


def _first_int(pattern, text):
    found = _first(pattern, text)
    return int(found) if found else None


def _grounded(phrase, source):
    src = source.lower()
    words = re.findall(r"[a-z0-9]{4,}", phrase.lower())
    return all(word in src for word in words)
