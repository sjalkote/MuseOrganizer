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
             "snippet": "Mock listing result. Add SERPAPI_API_KEY for live results."}
            for site in ("cars.com", "autotrader.com", "toyota.com")
        ]}
    if engine == "google_maps":
        return {"local_results": [
            {"title": f"{params['q']} #{i} (mock)", "address": f"{100 * i} Main St, {params.get('location', '')}",
             "rating": 4.5, "gps_coordinates": {"latitude": 30.27 + i / 100, "longitude": -97.74}}
            for i in (1, 2, 3)
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
