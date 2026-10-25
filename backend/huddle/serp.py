"""SerpApi client. Cache-first: every live response is saved under fixtures/serpapi/ and replayed.

With no SERPAPI_API_KEY, cache misses return a small synthetic response shaped like the real one.
Docs: https://serpapi.com/search-api, /google-maps-api, /google-maps-directions-api, /extract-api.
"""
import hashlib
import json
import os
from pathlib import Path

import httpx

URL = "https://serpapi.com/search"
KEY = os.environ.get("SERPAPI_API_KEY")
CACHE = Path(__file__).parent.parent / "fixtures" / "serpapi"


def _cache_path(params):
    digest = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]
    return CACHE / f"{params['engine']}-{digest}.json"


def _synthetic(params):
    engine = params["engine"]
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
        return {"best_flights": [{"flights": legs, "layovers": [{"id": "LAX"}], "price": 1148 * adults}],
                "other_flights": [{"flights": legs, "layovers": [{"id": "LAX"}], "price": (1190 + 40 * i) * adults}
                                  for i in range(13)]}
    if engine == "google_hotels":
        area = params["q"].removesuffix(" hotels")
        return {"properties": [
            {"name": f"{area} {kind} (mock)", "overall_rating": rating,
             "rate_per_night": {"lowest": f"${rate}", "extracted_lowest": rate}}
            for kind, rating, rate in [("Central Hotel", 4.4, 168), ("Garden Inn", 4.6, 214), ("Station Hostel", 4.1, 62)]
        ]}
    if engine == "google_shopping":
        return {"shopping_results": [
            {"title": f"{params['q'].split(',')[0]} · {34100 + 900 * i:,} mi (mock)", "source": "cars.com",
             "extracted_price": 27495 + 350 * i, "price": f"${27495 + 350 * i:,}"}
            for i in range(6)
        ]}
    raise KeyError(f"no mock for engine {engine}")


def search(engine, **params):
    params = {"engine": engine, **params}
    path = _cache_path(params)
    if path.exists():
        return json.loads(path.read_text())
    if not KEY:
        return _synthetic(params)
    r = httpx.get(URL, params={**params, "api_key": KEY}, timeout=60)
    r.raise_for_status()
    CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text(r.text)
    return r.json()
