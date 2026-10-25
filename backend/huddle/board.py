"""The trip board: live options from SerpApi, trade-offs written by Muse Spark, and a price watch on what can be booked.

The app sends the trip's facts (airports, dates, stays, what to look for) and gets back the options to vote on.
Flights and hotels are watched automatically, so the group hears about drops without asking.
"""
from datetime import date

from . import serp, watch
from .muse import muse


def _day(d):
    d = date.fromisoformat(d)
    return f"{d:%b} {d.day}"


def _hours(minutes):
    return f"{minutes // 60}h {minutes % 60:02d}m" if minutes else ""


def _airline(option):
    names = [l.get("airline", "") for l in option.get("flights", [])]
    return names[0] if names else "Flight"


def flights(trip, plan_id, n):
    out = []
    for f in trip.get("flights", []):
        params = {"departure_id": f["from"], "arrival_id": f["to"], "outbound_date": f["depart"],
                  "return_date": f["return"], "adults": n, "currency": "USD", "hl": "en"}
        data = serp.search("google_flights", **params)
        seen = set()
        for o in data.get("best_flights", []) + data.get("other_flights", []):
            airline = _airline(o)
            if airline in seen or not o.get("price"):
                continue
            seen.add(airline)
            via = ", ".join(l["id"] for l in o.get("layovers", []))
            detail = " · ".join(filter(None, [f"{f['from']} → {f['to']}", f"via {via}" if via else "nonstop",
                                              _hours(o.get("total_duration"))]))
            out.append({"category": "flights", "title": airline, "detail": detail, "price": o["price"] / n,
                        "unit": "per person", "source": "Google Flights",
                        "facts": {"stops": len(o.get("layovers", [])), "hours": (o.get("total_duration") or 0) / 60,
                                  "airport": f["to"]},
                        "watch": dict(engine="google_flights", params=params, match=airline.removesuffix(" (mock)"),
                                      label=f"{airline} · {f['from']} → {f['to']}",
                                      detail=f"{_day(f['depart'])} – {_day(f['return'])} · {n} travelers",
                                      unit="per person", needed_by=f["depart"], seed=data)})
            if len(seen) == 3:
                break
    return out


def stays(trip, plan_id, n):
    out = []
    for s in trip.get("stays", []):
        params = {"q": f"{s['area']} hotels", "check_in_date": s["checkIn"], "check_out_date": s["checkOut"],
                  "adults": n, "currency": "USD", "hl": "en", "rooms": s.get("rooms", 1)}
        data = serp.search("google_hotels", **params)
        priced = [p for p in data.get("properties", [])[:6] if p.get("rate_per_night", {}).get("extracted_lowest")]
        nights = (date.fromisoformat(s["checkOut"]) - date.fromisoformat(s["checkIn"])).days
        for p in sorted(priced, key=lambda p: -p.get("overall_rating", 0))[:2]:
            rate = p["rate_per_night"]["extracted_lowest"]
            detail = " · ".join(filter(None, [s["area"], f"{p['overall_rating']} rating" if p.get("overall_rating") else "",
                                              f"{nights} nights"]))
            out.append({"category": "stays", "title": p["name"], "detail": detail, "price": rate,
                        "unit": "per room, night", "source": "Google Hotels", "link": p.get("link"),
                        "facts": {"rating": p.get("overall_rating"), "nights": nights, "area": s["area"]},
                        "watch": dict(engine="google_hotels", params=params, match=p["name"].removesuffix(" (mock)"),
                                      label=p["name"], detail=f"{_day(s['checkIn'])} – {_day(s['checkOut'])} · {s['area']}",
                                      unit="per night", needed_by=s["checkIn"], seed=data)})
    return out


def activities(trip):
    out = []
    for q in trip.get("activities", []):
        data = serp.search("google_maps", q=q, type="search")
        for p in data.get("local_results", [])[:3]:
            area = q.split(",")[-1].strip() if "," in q else ""
            detail = " · ".join(str(x) for x in [area, p.get("type"), f"{p['rating']} rating" if p.get("rating") else ""] if x)
            out.append({"category": "activities", "title": p["title"], "detail": detail, "price": None,
                        "priceLabel": p.get("price") or "", "unit": "", "source": "Google Maps",
                        "facts": {"rating": p.get("rating"), "reviews": p.get("reviews"), "type": p.get("type")}})
    return out


def draft_tradeoff(o, cheapest):
    """A plain trade-off from the facts, used when Muse is offline and as Muse's starting point."""
    f = o["facts"]
    if o["category"] == "flights":
        cost = "Cheapest" if o["price"] <= cheapest else f"${o['price'] - cheapest:,.0f} more than the cheapest"
        stops = "Nonstop" if not f["stops"] else f"{f['stops']} stop"
        return f"{cost}. {stops}, about {f['hours']:.0f} hours."
    if o["category"] == "stays":
        return f"Rated {f['rating']} in {f['area']}. ${o['price'] * f['nights']:,.0f} a room for {f['nights']} nights."
    rating = f"Rated {f['rating']}" if f.get("rating") else "Popular"
    reviews = f" ({f['reviews']:,} reviews)" if f.get("reviews") else ""
    kind = f.get("type") or "Worth a look"
    return f"{rating}{reviews}. {kind}."


def build(plan_id, trip):
    n = int(trip.get("travelers") or 1)
    options = flights(trip, plan_id, n) + stays(trip, plan_id, n) + activities(trip)
    for i, o in enumerate(options):
        o["id"] = f"{o['category']}-{i}"
    for cat in ("flights", "stays"):
        prices = [o["price"] for o in options if o["category"] == cat]
        for o in options:
            if o["category"] == cat:
                o["draft"] = draft_tradeoff(o, min(prices))
    for o in options:
        o.setdefault("draft", draft_tradeoff(o, 0))
    try:
        written = muse.tradeoffs([{"id": o["id"], "category": o["category"], "title": o["title"], "detail": o["detail"],
                                   "price": o["price"], "unit": o["unit"], "draft": o["draft"], **o["facts"]} for o in options])
    except Exception:
        written = {}
    for o in options:
        o["tradeoff"] = written.get(o["id"]) or o["draft"]
        spec = o.pop("watch", None)
        if spec:
            w = watch.find(plan_id, spec["engine"], spec["params"], spec["match"])
            if not w:
                seed = spec.pop("seed")
                w = watch.create(plan_id, o["category"], price=o["price"], seed=seed, **spec)
            o["watchId"] = w["id"]
        o.pop("facts")
        o.pop("draft")
    return {"options": options, "watches": watch.for_plan(plan_id),
            "live": {"muse": _muse_live(), "serpapi": serp.LIVE}}


def _muse_live():
    from . import muse as m
    return m.LIVE
