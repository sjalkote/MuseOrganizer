import json
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from huddle import api, google, workspace

client = TestClient(api.app)

TRIP = {
    "folderName": "Japan 2027", "kind": "trip", "members": ["Devin", "Sam", "Maya", "Jordan"],
    "context": {"budgetPerPerson": "2500"},
    "calls": [{"id": f"c{i}", "engine": e, "query": q} for i, (e, q) in enumerate([
        ("google_flights", "AUS → HND, Mar 26 – Apr 4, 4 adults"),
        ("google_hotels", "Shinjuku, Mar 26 – 30, 2 rooms"),
        ("google_hotels", "Kyoto Higashiyama, Mar 30 – Apr 2"),
        ("google_maps", "best ramen and izakaya, Shinjuku"),
        ("google_maps", "top things to do, Kyoto"),
        ("google", "Shinkansen Tokyo to Kyoto fare"),
    ])],
    "files": [{"id": "budget", "name": "Budget Tracker", "kind": "sheet"},
              {"id": "daily", "name": "Daily", "kind": "doc"},
              {"id": "food", "name": "Places to stay + food", "kind": "doc"}],
}

CAR = {
    "folderName": "Our next car", "kind": "decision", "members": ["Mom", "Dad"],
    "context": {"buyoutPrice": "24180", "decision": "buy out the RAV4"},
    "calls": [{"id": f"k{i}", "engine": e, "query": q} for i, (e, q) in enumerate([
        ("google_shopping", "2023 Toyota RAV4 XLE, ~37k mi, Austin"),
        ("google", "auto loan rates for a lease buyout"),
        ("google_maps", "Toyota dealers near Austin"),
    ])],
    "files": [{"id": "cost", "name": "Cost comparison", "kind": "sheet", "summary": "4 options",
               "content": {"columns": ["Option", "Monthly"], "rows": [["Buy out", "$478"]], "footer": "Simulated account data"}},
              {"id": "market", "name": "Market prices", "kind": "sheet"},
              {"id": "prep", "name": "Dealer visit prep", "kind": "doc"},
              {"id": "why", "name": "Decision summary", "kind": "doc"}],
}


def build(plan):
    r = client.post("/plans/p1/workspace", json=plan)
    assert r.status_code == 202, r.text
    events, kind = [], None
    with client.stream("GET", f"/builds/{r.json()['buildId']}/events") as s:
        for line in s.iter_lines():
            if line.startswith("event: "):
                kind = line[7:]
            elif line.startswith("data: "):
                events.append((kind, json.loads(line[6:])))
    return events


def folder(name):
    return workspace.MOCK_ROOT / workspace.slug(name)


def test_search_params_read_the_query():
    p = workspace.search_params(TRIP["calls"][0], TRIP)
    assert p | {"adults": 4} == p and (p["departure_id"], p["arrival_id"]) == ("AUS", "HND")
    assert (p["outbound_date"], p["return_date"]) == ("2027-03-26", "2027-04-04")
    h = workspace.search_params(TRIP["calls"][1], TRIP)
    assert (h["q"], h["check_in_date"], h["check_out_date"]) == ("Shinjuku hotels", "2027-03-26", "2027-03-30")
    assert workspace.date_range("Dec 28 – Jan 3", 2026) == (date(2026, 12, 28), date(2027, 1, 3))


def test_trip_build_streams_every_step_with_the_apps_ids():
    events = build(TRIP)
    kinds = [k for k, _ in events]
    assert kinds == ["researching", "researched"] * 6 + ["writing", "wrote"] * 3 + ["finished"]
    assert [d["id"] for k, d in events if k == "researched"] == [c["id"] for c in TRIP["calls"]]
    assert [d["id"] for k, d in events if k == "wrote"] == ["budget", "daily", "food"]
    done = events[-1][1]
    assert done["folderName"] == "Japan 2027" and done["url"].startswith("https://drive.google.com/drive/folders/")
    assert sorted(p.name for p in folder("Japan 2027").iterdir()) == ["Budget Tracker.csv", "Daily.md", "Places to stay + food.md"]


def test_budget_uses_each_hotel_searchs_own_nights():
    build(TRIP)
    rows = (folder("Japan 2027") / "Budget Tracker.csv").read_text()
    assert "· 4 nights" in rows and "· 3 nights" in rows and "9 nights" not in rows
    assert "budget by" in rows and "Google Flights" in rows


def test_daily_has_every_day_and_tight_bullets():
    build(TRIP)
    text = (folder("Japan 2027") / "Daily.md").read_text()
    assert text.count("## Day ") == 10
    assert "Free day: nothing booked yet" in text
    assert "Land at HND" in text and "Check in at" in text
    for section in text.split("## ")[1:]:
        assert "\n- " in section and "\n\n- " not in section.split("\n", 2)[2]
    # Shinjuku days never get Kyoto sights.
    shinjuku = [s for s in text.split("## ")[1:] if "· Shinjuku" in s]
    assert shinjuku and not any("Kyoto" in s for s in shinjuku)


def test_car_files_are_marked_simulated_and_unknown_files_pass_through():
    events = build(CAR)
    assert [d["id"] for k, d in events if k == "wrote"] == ["cost", "market", "prep", "why"]
    out = folder("Our next car")
    for name in ("Market prices.csv", "Dealer visit prep.md", "Decision summary.md", "Cost comparison.csv"):
        assert "Simulated account data" in (out / name).read_text()
    assert "Buy out,$478" in (out / "Cost comparison.csv").read_text()
    assert "5.9% APR" in (out / "Dealer visit prep.md").read_text()
    files = {f["id"]: f for f in events[-1][1]["files"]}
    assert files["market"]["content"]["rows"][-1][0] == "Average of 6"


def test_failed_build_cleans_up_and_reports():
    plan = {**TRIP, "folderName": "Broken trip",
            "files": TRIP["files"] + [{"id": "x", "name": "Market prices", "kind": "sheet"}]}
    events = build(plan)
    assert events[-1][0] == "failed" and "Google Shopping" in events[-1][1]["message"]
    assert not folder("Broken trip").exists()


def test_cancel_deletes_what_was_written():
    b = workspace.Build()

    class Drive(workspace.MockDrive):
        def create_doc(self, *a):
            b.cancelled = True  # the user taps Cancel while Muse writes
            return super().create_doc(*a)

    workspace.run(b, {**TRIP, "folderName": "Cancelled trip"}, Drive, pace=0)
    assert b.events[-1][0] == "cancelled" and b.done
    assert not folder("Cancelled trip").exists()


def test_unreadable_flight_query_fails_clearly():
    plan = {**TRIP, "folderName": "Vague", "calls": [{"id": "c", "engine": "google_flights", "query": "Japan sometime"}]}
    events = build(plan)
    assert events[-1][0] == "failed" and "send params" in events[-1][1]["message"]


def test_google_needs_sign_in_once_configured(monkeypatch):
    assert client.get("/auth/google/status").json() == {"mode": "mock", "configured": False, "connected": False}
    monkeypatch.setattr(google, "CLIENT_ID", "id")
    monkeypatch.setattr(google, "CLIENT_SECRET", "secret")
    assert client.post("/plans/p1/workspace", json=TRIP).status_code == 409
    r = client.get("/auth/google/start", follow_redirects=False)
    assert r.status_code == 307 and "drive.file" in r.headers["location"] and "access_type=offline" in r.headers["location"]


def test_doc_requests_count_utf16_and_style_blocks():
    reqs = google.doc_requests([{"type": "title", "text": "Trip 🗾"}, {"type": "bullet", "text": "A → B"}])
    assert reqs[0]["insertText"]["text"] == "Trip 🗾\nA → B\n"
    # "Trip 🗾\n" is 8 UTF-16 units (the emoji takes two).
    assert reqs[1]["updateParagraphStyle"]["range"] == {"startIndex": 1, "endIndex": 9}
    assert reqs[2]["createParagraphBullets"]["range"] == {"startIndex": 9, "endIndex": 15}
