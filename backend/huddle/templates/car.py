"""Family Toyota car decision template."""
from .. import finance

# Public assumptions shown on every card. ponytail: fixed rates, pull live Toyota offers via SerpApi later.
ASSUME = {"apr": 0.065, "months": 60, "down_pct": 0.10, "tax_pct": 0.0625,
          "lease_months": 36, "residual_pct": 0.60, "money_factor": 0.0025, "lease_fees": 650}
PLAN_NAMES = {"cash": "paying cash", "finance": "financing", "lease": "leasing"}

# Approximate 2025 base-trim MSRP / combined MPG / max seats / cargo behind 2nd row (cu ft).
# awd = AWD or 4WD available on some trim.
CATALOG = [
    {"name": "Corolla", "msrp": 22325, "mpg": 35, "seats": 5, "cargo": 13, "awd": False},
    {"name": "Corolla Cross", "msrp": 24135, "mpg": 32, "seats": 5, "cargo": 25, "awd": True},
    {"name": "Prius", "msrp": 28350, "mpg": 57, "seats": 5, "cargo": 20, "awd": True},
    {"name": "Camry", "msrp": 28400, "mpg": 51, "seats": 5, "cargo": 15, "awd": True},
    {"name": "RAV4", "msrp": 28850, "mpg": 30, "seats": 5, "cargo": 38, "awd": True},
    {"name": "RAV4 Hybrid", "msrp": 32850, "mpg": 40, "seats": 5, "cargo": 38, "awd": True},
    {"name": "Tacoma", "msrp": 31590, "mpg": 21, "seats": 5, "cargo": 0, "awd": True},
    {"name": "Sienna", "msrp": 39185, "mpg": 36, "seats": 8, "cargo": 75, "awd": True},
    {"name": "Highlander", "msrp": 39520, "mpg": 24, "seats": 8, "cargo": 41, "awd": True},
    {"name": "Grand Highlander", "msrp": 40860, "mpg": 24, "seats": 8, "cargo": 58, "awd": True},
    {"name": "4Runner", "msrp": 40770, "mpg": 19, "seats": 7, "cargo": 47, "awd": True},
]


def prepare(option, context):
    option["finance"] = finance.compare(option["msrp"], **ASSUME)
    option["est_monthly"] = option["finance"]["finance"]["monthly"]
    return option


def explain(option, mine):
    """Facts + plain-language draft for one member's private lease/buy/finance explanation."""
    f = option["finance"]
    c, fi, le = f["cash"], f["finance"], f["lease"]
    draft = (
        f"For the {option['name']} over {f['months']} months: "
        f"Leasing is about ${le['monthly']:,}/mo and you hand the car back at the end, so you keep $0 of it. "
        f"Financing is about ${fi['monthly']:,}/mo after ${fi['upfront']:,} down; after {f['months']} months "
        f"you'd own about ${fi['equity']:,} of the car, and you'd pay ${fi['interest']:,} in interest along the way. "
        f"Paying cash is ${c['upfront']:,} up front with no interest. "
        f"Counting what you keep, {PLAN_NAMES[f['best']]} costs the least."
    )
    cap = mine.get("max_monthly")
    if cap:
        fits = [PLAN_NAMES[k] for k in ("lease", "finance") if f[k]["monthly"] <= cap]
        verdict = {0: "neither monthly plan fits.", 1: f"{fits[0] if fits else ''} fits.",
                   2: "both leasing and financing fit."}[len(fits)]
        draft += f" Against your ${cap:,.0f}/mo limit, {verdict}"
    facts = {"car": option["name"], "plans": f, "assumptions": ASSUME, "your_max_monthly": cap}
    return facts, draft


TEMPLATE = {
    "id": "car",
    "title": "Family Toyota",
    "noun": "car",
    "card": "car",
    "catalog": CATALOG,
    "prepare": prepare,
    "explain": explain,
    "assumptions": ASSUME,
    # op "<=": option[attr] must be <= the strictest member value (min); ">=": max; "requires": any member.
    "constraint_schema": [
        {"key": "max_monthly", "label": "monthly payment up to", "type": "money", "kind": "hard",
         "attr": "est_monthly", "op": "<=", "miss": "over one of the monthly budgets",
         "ask": "What's the most you'd be comfortable paying per month? Only I will see this."},
        {"key": "min_seats", "label": "at least this many seats", "type": "int", "unit": "seat", "kind": "hard",
         "attr": "seats", "op": ">=", "miss": "short on seats for someone",
         "ask": "How many seats do you need?"},
        {"key": "needs_awd", "label": "needs AWD/4WD", "type": "bool", "kind": "hard",
         "attr": "awd", "op": "requires", "miss": "missing AWD, which someone needs",
         "keywords": ["awd", "4wd", "all-wheel", "snow", "ski"],
         "ask": "Do you need AWD for snow or trips?"},
        {"key": "w_fuel", "label": "importance of fuel economy (0-5)", "type": "weight", "kind": "soft",
         "attr": "mpg", "better": "higher", "default": 2, "keywords": ["gas", "mpg", "fuel", "commute"]},
        {"key": "w_space", "label": "importance of cargo space (0-5)", "type": "weight", "kind": "soft",
         "attr": "cargo", "better": "higher", "default": 2, "keywords": ["space", "cargo", "room", "trunk"]},
        {"key": "w_price", "label": "importance of low price (0-5)", "type": "weight", "kind": "soft",
         "attr": "msrp", "better": "lower", "default": 2, "keywords": ["cheap", "save", "afford", "price"]},
    ],
    # Run after ranking, only for the top options. "per": "option" runs once per option, "session" once.
    "search_plan": [
        {"per": "option", "engine": "google", "as": "listings", "limit": 3,
         "params": {"q": "2025 Toyota {name} for sale near {location}"},
         "pick": "organic_results", "fields": ["title", "link", "snippet"]},
        {"per": "session", "engine": "google_maps", "as": "dealers", "limit": 3,
         "params": {"q": "Toyota dealer", "location": "{location}", "type": "search"},
         "pick": "local_results", "fields": ["title", "address", "rating", "gps_coordinates", "place_id"]},
    ],
    # Public option fields Spark may see when explaining the top picks.
    "explain_fields": ["name", "msrp", "est_monthly", "mpg", "seats", "cargo", "score"],
}
