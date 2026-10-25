"""SerpApi client. Cache-first: every live response is saved under fixtures/serpapi/ and replayed.

Cache misses call SerpAPI. Synthetic responses are only for pytest (HUDDLE_OFFLINE=1).
Docs: https://serpapi.com/search-api, /google-maps-api, /google-maps-directions-api, /extract-api.
"""
import hashlib
import json
import math
import os
import time
from datetime import date, timedelta
from pathlib import Path

import httpx

URL = "https://serpapi.com/search"
CACHE = Path(__file__).parent.parent / "fixtures" / "serpapi"
LIVE = bool(os.environ.get("SERPAPI_API_KEY"))
# Mock prices move every DRIFT seconds on fresh searches, so price watches have something to react to offline.
DRIFT = float(os.environ.get("HUDDLE_MOCK_DRIFT", "60"))


def _cache_path(params):
    digest = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]
    return CACHE / f"{params['engine']}-{digest}.json"


def _drift(params, fresh):
    """1.0 for cached/board searches; for fresh mock searches, a slow wave of up to +-7% that differs per query."""
    if not fresh:
        return 1.0
    phase = int(hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:4], 16) / 65535 * 6.28
    return 1 + 0.07 * math.sin(time.time() / DRIFT + phase)


def _flight_insights(base, day):
    """Shaped like Google Flights' price_insights: two months of daily prices ending today."""
    today = date.today()
    history = [[int(time.mktime((today - timedelta(days=60 - i)).timetuple())),
                round(base * (1.08 + 0.06 * math.sin(i / 5)))] for i in range(0, 61, 3)]
    return {"lowest_price": base, "price_level": "typical", "typical_price_range": [round(base * 0.98), round(base * 1.2)],
            "price_history": history}


def _synthetic(params, fresh=False):
    engine = params["engine"]
    k = _drift({key: v for key, v in params.items() if key != "api_key"}, fresh)
    if engine == "google":
        q = params["q"]
        return {"organic_results": [
            {"title": f"{q} | {site} (mock)", "link": f"https://www.{site}/search?q={q.replace(' ', '+')}",
             "snippet": "Mock result: from $95, rates from 5.9% APR. Add SERPAPI_API_KEY for live results."}
            for site in ("cars.com", "autotrader.com", "toyota.com")
        ]}
    if engine == "google_maps":
        return {"local_results": [
            {"title": f"{params['q']} #{i} (mock)", "address": f"{100 * i} Main St, {params.get('location', '')}".rstrip(", "),
             "rating": 4.5, "price": "$$", "type": "Restaurant", "gps_coordinates": {"latitude": 30.27 + i / 100, "longitude": -97.74}}
            for i in (1, 2, 3)
        ]}
    if engine == "google_flights":
        adults = int(params.get("adults", 1))
        dep, arr, day = params["departure_id"], params["arrival_id"], params["outbound_date"]
        legs = [
            {"airline": "ANA (mock)", "flight_number": "NH 7", "departure_airport": {"id": dep, "time": f"{day} 06:10"},
             "arrival_airport": {"id": "LAX", "time": f"{day} 07:45"}},
            {"airline": "ANA (mock)", "flight_number": "NH 107", "departure_airport": {"id": "LAX", "time": f"{day} 10:30"},
             "arrival_airport": {"id": arr, "time": f"{day} 15:40"}},
        ]
        jal = [{**legs[0], "airline": "JAL (mock)", "flight_number": "JL 11", "arrival_airport": {"id": "DFW", "time": f"{day} 08:05"}},
               {**legs[1], "airline": "JAL (mock)", "flight_number": "JL 7", "departure_airport": {"id": "DFW", "time": f"{day} 10:50"}}]
        united = [{**legs[0], "airline": "United (mock)", "flight_number": "UA 1"}, {**legs[1], "airline": "United (mock)", "flight_number": "UA 837"}]
        return {"best_flights": [{"flights": legs, "layovers": [{"id": "LAX"}], "total_duration": 1060, "price": round(1148 * k) * adults},
                                 {"flights": jal, "layovers": [{"id": "DFW"}], "total_duration": 965, "price": round(1312 * k) * adults}],
                "other_flights": [{"flights": united, "layovers": [{"id": "SFO"}], "total_duration": 1090, "price": round((1089 + 40 * i) * k) * adults}
                                  for i in range(12)],
                "price_insights": _flight_insights(round(1148 * k) * adults, day)}
    if engine == "google_hotels":
        area = params["q"].removesuffix(" hotels")
        return {"properties": [
            {"name": f"{area} {kind} (mock)", "overall_rating": rating,
             "rate_per_night": {"lowest": f"${round(rate * k)}", "extracted_lowest": round(rate * k)}}
            for kind, rating, rate in [("Central Hotel", 4.4, 168), ("Garden Inn", 4.6, 214), ("Station Hostel", 4.1, 62)]
        ]}
    if engine == "google_shopping":
        return {"shopping_results": [
            {"title": f"{params['q'].split(',')[0]} · {34100 + 900 * i:,} mi (mock)", "source": "cars.com",
             "extracted_price": round((27495 + 350 * i) * k), "price": f"${round((27495 + 350 * i) * k):,}"}
            for i in range(6)
        ]}
    raise KeyError(f"no mock for engine {engine}")


def search(engine, fresh=False, **params):
    """Cached unless fresh=True (price watches), which always asks SerpApi and refreshes the cache."""
    params = {"engine": engine, **params}
    path = _cache_path(params)
    offline = os.environ.get("HUDDLE_OFFLINE") == "1"
    # Live responses are replayed from disk. Pytest stays on the synthetic responses. Fresh watches skip the cache.
    if path.exists() and not fresh and not offline:
        return json.loads(path.read_text())
    key = os.environ.get("SERPAPI_API_KEY")
    if not key:
        if offline:
            return _synthetic(params, fresh)
        raise RuntimeError("SERPAPI_API_KEY is required")
    if fresh:
        params["no_cache"] = "true"  # SerpApi's own hour-long cache would hide price changes
    r = httpx.get(URL, params={**params, "api_key": key}, timeout=60)
    r.raise_for_status()
    CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text(r.text)
    return r.json()
