import time
from datetime import date, timedelta

from fastapi.testclient import TestClient

from huddle import api, serp, watch, workspace
from huddle.muse import MockMuse

client = TestClient(api.app)

TRIP = {
    "travelers": 4, "budgetPerPerson": 2500,
    "flights": [{"from": "AUS", "to": "HND", "depart": "2027-03-26", "return": "2027-04-04"}],
    "stays": [{"area": "Shinjuku", "checkIn": "2027-03-26", "checkOut": "2027-03-30", "rooms": 2}],
    "activities": ["top things to do, Kyoto"],
}


def drift(monkeypatch, factor):
    monkeypatch.setattr(serp, "_drift", lambda params, fresh: factor if fresh else 1.0)


def test_board_has_options_with_tradeoffs_and_watches():
    out = client.post("/plans/board-test/board", json=TRIP).json()
    cats = [o["category"] for o in out["options"]]
    assert cats.count("flights") == 3 and cats.count("stays") == 2 and cats.count("activities") == 3
    first = out["options"][0]
    assert first["title"].startswith("ANA") and first["price"] == 1148 and first["unit"] == "per person"
    assert first["tradeoff"].startswith("$") or first["tradeoff"].startswith("Cheapest")
    assert all("watchId" in o for o in out["options"] if o["category"] != "activities")
    assert len(out["watches"]) == 5
    assert out["live"] == {"muse": False, "serpapi": False}


def test_board_is_idempotent():
    client.post("/plans/idem/board", json=TRIP)
    again = client.post("/plans/idem/board", json=TRIP).json()
    assert len(again["watches"]) == 5


def test_flight_watch_starts_with_google_history():
    out = client.post("/plans/history/board", json=TRIP).json()
    w = next(w for w in out["watches"] if w["category"] == "flights")
    assert len(w["history"]) > 5 and w["current"] == 1148 and w["neededBy"] == "2027-03-26"


def test_small_moves_stay_quiet(monkeypatch):
    out = client.post("/plans/quiet/board", json=TRIP).json()
    drift(monkeypatch, 1.01)
    assert client.post("/plans/quiet/watches/check").json()["alerts"] == []


def test_drop_creates_book_alert(monkeypatch):
    client.post("/plans/drop/board", json=TRIP)
    drift(monkeypatch, 0.85)
    res = client.post("/plans/drop/watches/check").json()
    ana = next(a for a in res["alerts"] if "ANA" in a["headline"])
    assert ana["verdict"] == "book" and ana["new"] < ana["old"]
    assert "dropped" in ana["headline"]
    w = next(w for w in res["watches"] if w["id"] == ana["watchId"])
    assert w["advice"]["id"] == ana["id"] and w["current"] == ana["new"]
    assert client.get("/alerts", params={"since": ana["at"] - 1}).json()["alerts"]


def test_alerts_since_filters(monkeypatch):
    client.post("/plans/since/board", json=TRIP)
    drift(monkeypatch, 1.2)
    client.post("/plans/since/watches/check")
    later = time.time() + 1
    assert client.get("/alerts", params={"since": later}).json()["alerts"] == []


def test_advice_rules():
    m = MockMuse()
    soon = (date.today() + timedelta(days=20)).isoformat()
    base = {"item": "ANA", "unit": "per person", "previous": 1200, "lowest_seen": 1100}
    assert m.advise({**base, "current": 1090})["verdict"] == "book"
    assert m.advise({**base, "current": 1150})["verdict"] == "watch"
    assert m.advise({**base, "current": 1300, "days_until": 20})["verdict"] == "book"
    assert m.advise({**base, "current": 1300, "days_until": 120})["verdict"] == "wait"
    assert watch.days_until(soon) == 20


def test_revise_budget_rows():
    rows = [["Flights · ANA via LAX", "$1,148", "$4,592", "Google Flights"],
            ["Hotel Gracery Shinjuku · 4 nights", "$336", "$1,344", "Google Hotels"],
            ["Total", "$1,484", "$5,936", ""]]
    w = {"category": "flights", "label": "ANA · AUS → HND"}
    new, footer = watch.revise(rows, w, 1000, {}, 4, 2500)
    assert new[0][1:3] == ["$1,000", "$4,000"] and new[2][1:3] == ["$1,336", "$5,344"]
    assert footer.startswith("Under the $2,500 budget by $1,164 each")
    hotel = {"category": "stays", "label": "Hotel Gracery Shinjuku"}
    new, _ = watch.revise(rows, hotel, 150, {"check_in_date": "2027-03-26", "check_out_date": "2027-03-30", "rooms": 2}, 4)
    assert new[1][2] == "$1,200"
    assert watch.revise(rows, {"category": "activities", "label": "x"}, 1, {}, 4) is None


def test_price_drop_rewrites_budget_sheet(monkeypatch, tmp_path):
    folder = workspace.MockDrive(tmp_path).create_folder("Japan 2027")
    url = workspace.MockDrive(tmp_path).create_sheet(folder, "Budget Tracker", ["Item", "Per person", "Group of 4", "Source"],
                                                     [["Flights · ANA via LAX", "$1,148", "$4,592", "Google Flights"],
                                                      ["Total", "$1,148", "$4,592", ""]], "footer")
    client.post("/plans/sheet/board", json=TRIP)
    watch.register_budget("sheet", url, 4, 2500)
    drift(monkeypatch, 0.85)
    alerts = client.post("/plans/sheet/watches/check").json()["alerts"]
    flight = next(a for a in alerts if "ANA" in a["headline"])
    _, rows = workspace.MockDrive().read_sheet(url)
    assert rows[0][1] == f"${flight['new']:,.0f}" and rows[-1][0] == "Total"
    assert "updated by Muse price watch" in workspace.MockDrive.path_of(url).read_text()


def test_generic_car_watch():
    w = client.post("/plans/car/watches", json={
        "category": "car", "label": "Used RAV4 XLE near Austin", "engine": "google_shopping",
        "params": {"q": "2023 Toyota RAV4 XLE, Austin"}, "unit": "per car"}).json()
    assert w["current"] == 27495 and w["category"] == "car"
    assert client.delete(f"/watches/{w['id']}").json() == {"removed": w["id"]}
    assert client.get("/plans/car/watches").json()["watches"] == []


def _titles(setup):
    return [tab["title"] for tab in setup["tabs"]]


def test_tabs_follow_the_plan():
    from huddle import tabs
    movie = tabs.infer("Friday movie night", "general", "")
    assert movie["style"] == "event" and _titles(movie) == ["Overview", "Theaters"]
    with_food = tabs.infer("Friday movie night", "general", "", "Find showtimes and somewhere to eat after.")
    assert _titles(with_food) == ["Overview", "Theaters", "Food"]
    dinner = tabs.infer("Bea's birthday dinner", "gathering", "where should we go for dinner near Allston, 6 of us, $40 each, one vegan")
    assert dinner["style"] == "dinner" and _titles(dinner) == ["Overview", "Places", "Who's in"]
    assert "Vegan option" in dinner["chips"] and "Near Allston" in dinner["chips"]
    japan = tabs.infer("Japan Trip 2027", "trip", "flights from Austin, 4 of us, $2,500 each")
    assert _titles(japan) == ["Overview", "Flights", "Stays", "Do", "Money"]
    car = tabs.infer("Our next car", "decision", "buy out the RAV4 lease")
    assert car["style"] == "purchase" and "flights" not in [tab["id"] for tab in car["tabs"]]


def test_setup_drops_tabs_and_chips_the_plan_never_mentioned():
    out = client.post("/plans/setup", json={"name": "Friday movie night", "kind": "general", "request": ""}).json()
    assert out["live"] is False
    assert _titles(out) == ["Overview", "Theaters"]
    invented = client.post("/plans/setup", json={"name": "Notes", "kind": "general", "request": "bring a notebook"}).json()
    # Muse is off in tests, so this is the fallback. A notes plan is not a flight search.
    assert "flights" not in [tab["id"] for tab in invented["tabs"]]


def test_muse_module_choice_is_what_gets_searched(monkeypatch):
    monkeypatch.setenv("MUSE_ENABLED", "1")
    monkeypatch.setenv("MODEL_API_KEY", "test")
    monkeypatch.setattr("huddle.muse.muse.choose_module", lambda facts: {"module": "places", "subject": "dinner near Allston"})
    monkeypatch.setattr("huddle.muse.muse.answer", lambda question, plan: "Muse: " + plan["search"][0]["title"])
    out = client.post("/plans/mod/ask", json={
        "question": "track the price of dinner near Allston",
        "name": "Bea's birthday dinner",
        "kind": "gathering",
    }).json()
    assert out["options"][0]["source"] == "Google Maps"
    assert out["text"].startswith("I added") and "Food" in out["text"] and "Muse:" in out["text"]
    assert out["list"]["title"] == "Food"


def test_ask_uses_watches():
    client.post("/plans/ask/board", json=TRIP)
    out = client.post("/plans/ask/ask", json={"question": "which flight is cheapest?"}).json()
    assert out["live"] is False and "watching 3 prices" in out["text"] and "per person" in out["text"]
    assert out["options"] == []


def test_ask_finds_places_with_serp():
    out = client.post("/plans/places/ask", json={
        "question": "@Muse where should we go for dinner near Allston",
        "name": "Bea's birthday dinner",
    }).json()
    assert out["live"] is False
    assert "Google Maps" in out["text"] and "(mock)" in out["text"]
    assert out["options"][0]["source"] == "Google Maps"
    assert "Main St" in out["options"][0]["detail"]


def test_car_lookup_skips_the_bottom_of_a_price_range():
    from huddle import lookup
    data = {"organic_results": [
        {"title": "RAV4 for sale", "snippet": "Prices currently range from $2,800 to $57,279.", "link": "https://example.com"},
        {"title": "Used RAV4", "snippet": "Low Price: $26,216 Average Price: $31,541", "link": "https://example.com/2"},
    ]}
    priced = lookup._keep_typical(lookup._sale_prices(data))
    assert priced[0][0] == 26216


def test_ask_starts_a_price_watch():
    out = client.post("/plans/track/ask", json={
        "question": "@Muse track the price", "name": "Used RAV4", "kind": "decision",
    }).json()
    assert out["live"] is False and "$27,495" in out["text"] and "watching" in out["text"]
    watches = client.get("/plans/track/watches").json()["watches"]
    assert len(watches) == 1 and watches[0]["current"] == 27495


def test_status():
    assert client.get("/status").json()["muse"] is False


def fake_muse(reply):
    """A real Muse client whose HTTP calls return `reply` as a tool call, recording what was sent."""
    import json as _json

    import httpx

    from huddle.muse import Muse

    sent = []

    def handle(request):
        body = _json.loads(request.content)
        sent.append(body)
        tool = body["tools"][0]["function"]["name"]
        return httpx.Response(200, json={"choices": [{"message": {"tool_calls": [
            {"function": {"name": tool, "arguments": _json.dumps(reply)}}]}}]})

    m = Muse("test-key")
    m.http = httpx.Client(base_url="https://api.meta.ai/v1", transport=httpx.MockTransport(handle))
    return m, sent


def test_live_muse_advice_request_and_parse():
    m, sent = fake_muse({"verdict": "book", "headline": "ANA dropped $64", "reason": "Lowest in 60 days."})
    out = m.advise({"item": "ANA", "previous": 1212, "current": 1148, "lowest_seen": 1148})
    assert out == {"verdict": "book", "headline": "ANA dropped $64", "reason": "Lowest in 60 days."}
    assert sent[0]["tool_choice"]["function"]["name"] == "record_advice"
    assert "FACTS" in sent[0]["messages"][1]["content"]


def test_live_muse_rejects_bad_verdict_and_watch_falls_back(monkeypatch):
    m, _ = fake_muse({"verdict": "maybe", "headline": "x", "reason": "y"})
    import pytest
    with pytest.raises(ValueError):
        m.advise({"item": "ANA", "previous": 1, "current": 1, "lowest_seen": 1})
    monkeypatch.setattr(watch, "muse", m)
    w = {"label": "ANA", "unit": "per person", "low": 1100, "high": 1300, "neededBy": None, "history": []}
    assert watch.advise(w, 1200, 1090)["verdict"] == "book"  # rule of thumb when Muse misbehaves


def test_live_muse_tradeoffs():
    m, _ = fake_muse({"tradeoffs": [{"id": "flights-0", "text": "Cheapest, one stop"}]})
    assert m.tradeoffs([{"id": "flights-0"}]) == {"flights-0": "Cheapest, one stop"}
