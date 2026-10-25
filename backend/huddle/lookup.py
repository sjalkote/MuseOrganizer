"""Chat lookups. SerpAPI finds places and prices. Muse is optional polish on top of those results."""
import os
import re

from . import serp, watch

_WATCH_QUESTION = ("which", "cheapest", "lowest", "book now", "should we book")
_PLACE = ("where", "destination", "hotel", "stay", "restaurant", "dinner", "food", "near",
          "things to do", "movie", "showtime", "find", "go")
_PRICE = ("price", "cost", "how much", "track", "watch", "cheap", "fare", "for sale")
_FLIGHT = ("flight", "fly", "airfare")


def _has(low, words):
    return any(re.search(rf"\b{re.escape(word)}\b", low) for word in words)


def about_existing_watches(question, watches):
    """A question about prices already being watched, not a new search."""
    if not watches:
        return False
    low = question.lower()
    if _has(low, ("where", "find", "near", "destination", "track")):
        return False
    return _has(low, _WATCH_QUESTION)


def answer(plan_id, question, name="", kind=""):
    subject = _subject(question, name)
    low = f"{subject} {question}".lower()
    facts = []
    options = []
    watched = None

    if _has(low, _FLIGHT) and (pair := re.search(r"\b([A-Za-z]{3})\s*(?:→|->|to|-)\s*([A-Za-z]{3})\b", question)):
        text, facts, options, watched = _flights(plan_id, subject, [pair.group(1).upper(), pair.group(2).upper()], question)
    elif _is_place(low) and not _is_price(low):
        text, facts, options = _places(subject)
    elif _is_price(low) or kind == "decision":
        text, facts, options, watched = _prices(plan_id, subject, low, kind)
    else:
        text, facts, options = _web(subject)

    return {
        "text": text,
        "live": bool(os.environ.get("SERPAPI_API_KEY")),
        "facts": facts,
        "options": options,
        "watchId": watched["id"] if watched else None,
    }


def _subject(question, name):
    q = re.sub(r"@\w+", "", question)
    q = re.sub(
        r"\b(please|can you|could you|track the price|watch the price|what's a good price|whats a good price|"
        r"how much is|how much|where should we go|find me|find)\b",
        "", q, flags=re.I)
    q = re.sub(r"\s+", " ", q).strip(" ?.")
    return q or name or "this plan"


def _is_place(low):
    return _has(low, _PLACE)


def _is_price(low):
    return _has(low, _PRICE)


def _places(subject):
    data = serp.search("google_maps", q=subject, type="search")
    places = data.get("local_results") or []
    if not places:
        return _web(subject)
    lines = ["Places from Google Maps:"]
    facts, options = [], []
    for i, place in enumerate(places[:4]):
        bits = [place.get("title"), place.get("address")]
        if place.get("rating"):
            bits.append(f"{place['rating']} rating")
        if place.get("price"):
            bits.append(str(place["price"]))
        line = " · ".join(str(bit) for bit in bits if bit)
        lines.append(line)
        facts.append({"title": place.get("title"), "address": place.get("address"), "rating": place.get("rating"),
                      "price": place.get("price")})
        options.append({
            "id": f"place-{i}", "category": "activities", "title": place.get("title") or subject,
            "detail": " · ".join(str(bit) for bit in (place.get("address"), place.get("type")) if bit),
            "price": None, "priceLabel": place.get("price") or "", "unit": "",
            "tradeoff": line, "source": "Google Maps", "link": place.get("link"), "watchId": None,
        })
    return "\n".join(lines), facts, options


def _prices(plan_id, subject, low, kind):
    car = kind == "decision" or _has(low, ("car", "lease", "for sale", "rav4", "dealer"))
    if car:
        data = serp.search("google", q=f"{subject} for sale")
        priced = _sale_prices(data)
        engine, params = "google", {"q": f"{subject} for sale"}
        if not priced:
            data = serp.search("google_shopping", q=subject)
            priced = _shopping_prices(data)
            engine, params = "google_shopping", {"q": subject}
    else:
        data = serp.search("google_shopping", q=subject)
        priced = _shopping_prices(data)
        engine, params = "google_shopping", {"q": subject}
        if not priced:
            data = serp.search("google", q=subject)
            priced = _sale_prices(data)
            engine, params = "google", {"q": subject}
    if not priced:
        text, facts, options = _web(subject)
        return text, facts, options, None
    if car:
        priced = _keep_typical(priced)
    price, title, source, link = priced[0]
    # Search-result titles ("RAV4 for sale in Austin") are the page, not the car. Watch the thing the group asked about.
    label = subject if car else (title or subject)
    unit = "per car" if car else "each"
    saved = watch.find(plan_id, engine, params) or watch.create(
        plan_id, "car" if car else "shopping", label, engine, params,
        detail=subject, unit=unit, price=price, seed=data)
    text = f"{label} is ${price:,.0f} on {source}. I'll keep watching that price."
    option = {
        "id": saved["id"], "category": "activities", "title": label,
        "detail": subject, "price": price, "priceLabel": f"${price:,.0f}", "unit": unit,
        "tradeoff": text, "source": source, "link": link, "watchId": saved["id"],
    }
    return text, [{"title": label, "price": price, "source": source}], [option], saved


def _flights(plan_id, subject, codes, question):
    dates = re.findall(r"\d{4}-\d{2}-\d{2}", question)
    if len(codes) < 2 or not dates:
        text, facts, options = _web(subject)
        return text, facts, options, None
    params = {
        "departure_id": codes[0], "arrival_id": codes[1], "outbound_date": dates[0],
        "return_date": dates[1] if len(dates) > 1 else dates[0], "adults": "1", "currency": "USD", "hl": "en",
    }
    data = serp.search("google_flights", **{k: v for k, v in params.items()})
    offers = [o for o in data.get("best_flights", []) + data.get("other_flights", []) if o.get("price")]
    if not offers:
        text, facts, options = _web(subject)
        return text, facts, options, None
    best = min(offers, key=lambda o: o["price"])
    airline = next((leg.get("airline") for leg in best.get("flights", []) if leg.get("airline")), "Flight")
    price = best["price"]
    label = f"{airline} {codes[0]} → {codes[1]}"
    saved = watch.find(plan_id, "google_flights", params) or watch.create(
        plan_id, "flights", label, "google_flights", params, match=airline, unit="per person", price=price, seed=data)
    text = f"{label} is ${price:,.0f} per person. I'll keep watching that fare."
    option = {
        "id": saved["id"], "category": "flights", "title": label,
        "detail": f"{params['outbound_date']} – {params['return_date']}", "price": price,
        "priceLabel": f"${price:,.0f}", "unit": "per person", "tradeoff": text,
        "source": "Google Flights", "link": None, "watchId": saved["id"],
    }
    return text, [{"title": label, "price": price}], [option], saved


def _web(subject):
    data = serp.search("google", q=subject)
    rows = data.get("organic_results") or []
    if not rows:
        return f"I searched for {subject} and didn't get anything usable back.", [], []
    lines = [f"From Google, for {subject}:"]
    facts, options = [], []
    for i, row in enumerate(rows[:3]):
        title = row.get("title") or subject
        snippet = row.get("snippet") or ""
        lines.append(" · ".join(part for part in (title, snippet) if part))
        facts.append({"title": title, "snippet": snippet, "link": row.get("link")})
        options.append({
            "id": f"web-{i}", "category": "activities", "title": title, "detail": snippet,
            "price": None, "priceLabel": "", "unit": "", "tradeoff": snippet or title,
            "source": "Google", "link": row.get("link"), "watchId": None,
        })
    return "\n".join(lines), facts, options


def _keep_typical(priced):
    """Drop a teaser floor like "$2,800 to $57,279" when the other prices cluster much higher."""
    ordered = sorted(priced)
    mid = ordered[len(ordered) // 2][0]
    kept = [row for row in ordered if row[0] >= mid * 0.5]
    return kept or ordered


def _sale_prices(data):
    found = []
    for row in data.get("organic_results", []):
        blob = f"{row.get('title', '')} {row.get('snippet', '')}"
        for raw in re.findall(r"\$\s?([\d,]{4,})", blob):
            price = float(raw.replace(",", ""))
            if price >= 1000:
                found.append((price, row.get("title"), "Google", row.get("link")))
    return sorted(found)


def _shopping_prices(data):
    found = []
    for row in data.get("shopping_results", []):
        price = row.get("extracted_price")
        if price and price >= 1:
            found.append((float(price), row.get("title"), row.get("source") or "Google Shopping", row.get("link")))
    return sorted(found)
