from fastapi.testclient import TestClient

from huddle import api, engine
from huddle.templates import TEMPLATES


def family(mom_budget=650):
    s = engine.Session(TEMPLATES["car"], {"location": "Austin, TX"})
    for mid, name in [("mom", "Mom"), ("dad", "Dad"), ("teen", "Teen")]:
        s.add_member(mid, name)
    s.set_constraints("mom", {"max_monthly": mom_budget, "min_seats": 7, "w_fuel": 5})
    s.set_constraints("dad", {"max_monthly": 900, "needs_awd": True})
    s.set_constraints("teen", {"w_space": 5})
    return s


def test_merge_takes_strictest():
    assert engine.merged_limits(family()) == {"max_monthly": 650, "min_seats": 7, "needs_awd": True}


def test_fits_are_ranked_and_respect_every_limit():
    s = family(mom_budget=800)
    top = engine.run(s)
    assert [o["fits_all"] for o in top] == [True] * 3
    assert all(o["est_monthly"] <= 800 and o["seats"] >= 7 and o["awd"] for o in top)
    assert [o["score"] for o in top] == sorted((o["score"] for o in top), reverse=True)


def test_compromise_is_anonymous_and_private_ask_goes_only_to_mom():
    s = family()
    engine.run(s)
    text = s.group[-1]["text"]
    assert "closest" in text and "Sienna" in text
    for secret in ("650", "900", "Mom", "Dad"):
        assert secret not in text
    assert "650" in s.threads["mom"][-1]["text"]
    assert s.threads["dad"] == [] and s.threads["teen"] == []


def test_group_post_scrubs_private_values():
    s = family()
    s.post_group("Mom said she can only do $650 a month")
    assert s.group[-1]["text"] == engine.NEUTRAL
    s.post_group("Dad typed this himself: 900", author="dad")  # members may share their own words
    assert "900" in s.group[-1]["text"]


def test_spark_cannot_invent_numbers(monkeypatch):
    monkeypatch.setattr(engine.muse, "explain", lambda facts, draft: "It's only $499/mo!")
    assert engine.safe_explain({"est_monthly": 733}, "draft") == "draft"
    monkeypatch.setattr(engine.muse, "explain", lambda facts, draft: "About $733/mo.")
    assert engine.safe_explain({"est_monthly": 733}, "draft") == "About $733/mo."


def test_constraint_input_is_validated():
    s = family()
    s.set_constraints("teen", {"w_price": 99, "bogus": 1})
    assert s.private["teen"]["w_price"] == 5 and "bogus" not in s.private["teen"]
    try:
        s.set_constraints("teen", {"max_monthly": -5})
        assert False
    except ValueError:
        pass


def test_api_group_view_never_shows_private_values():
    c = TestClient(api.app)
    sid = c.post("/sessions", json={"template": "car", "context": {"location": "Austin, TX"}, "members": [
        {"id": "a", "name": "A"}, {"id": "b", "name": "B"}]}).json()["id"]
    c.post(f"/sessions/{sid}/private/a", json={"text": "I can do $612 a month, need 7 seats"})
    c.post(f"/sessions/{sid}/private/b", json={"text": "AWD please"})
    group = c.post(f"/sessions/{sid}/run").json()
    assert "612" not in " ".join(m["text"] for m in group)
    assert c.get(f"/sessions/{sid}/private/zzz").status_code == 404
