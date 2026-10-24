import json

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


def test_api_join_and_member_post():
    c = TestClient(api.app)
    sid = c.post("/sessions", json={"template": "car"}).json()["id"]
    j = c.post(f"/sessions/{sid}/join", json={"name": "Sam"}).json()
    assert j["members"][j["member_id"]] == "Sam" and j["title"] == "Family Toyota"
    group = c.post(f"/sessions/{sid}/group/{j['member_id']}", json={"text": "hi all"}).json()
    assert group[-1] == {"author": j["member_id"], "text": "hi all", "cards": []}


def test_rerun_without_changes_does_not_repost():
    s = family()
    engine.run(s)
    engine.run(s)
    assert len(s.group) == 1 and len(s.threads["mom"]) == 1


def test_voting_announces_winner_with_next_step_and_ties_go_to_rank():
    s = family(mom_budget=800)
    top = engine.run(s)
    assert engine.vote(s, "mom", top[1]["name"]) is None
    engine.vote(s, "dad", top[0]["name"])
    engine.vote(s, "dad", top[1]["name"])            # members can change their vote
    win = engine.vote(s, "teen", top[0]["name"])
    assert win["name"] == top[1]["name"] and s.winner == win["name"]
    assert "2 of 3 votes" in s.group[-1]["text"] and "test drive" in s.group[-1]["text"]
    try:
        engine.vote(s, "mom", top[0]["name"])
        assert False
    except ValueError:
        pass

    t = family(mom_budget=800)
    top = engine.run(t)
    for mid, i in [("mom", 2), ("dad", 1), ("teen", 0)]:
        engine.vote(t, mid, top[i]["name"])
    assert t.winner == top[0]["name"]                # three-way tie -> best ranked


def test_api_vote_state_and_persistence():
    c = TestClient(api.app)
    sid = c.post("/sessions", json={"template": "car", "members": [
        {"id": "a", "name": "A"}, {"id": "b", "name": "B"}]}).json()["id"]
    c.post(f"/sessions/{sid}/private/a", json={"text": "I can do $812 a month"})
    names = [card["option"]["name"] for card in c.post(f"/sessions/{sid}/run").json()[-1]["cards"]]
    st = c.post(f"/sessions/{sid}/vote/a", json={"option": names[0]}).json()
    assert st["tally"][names[0]] == 1 and st["my_vote"] == names[0] and st["voted"] == ["A"]
    assert c.get(f"/sessions/{sid}/state", params={"member": "b"}).json()["my_vote"] is None
    assert c.post(f"/sessions/{sid}/vote/b", json={"option": "Batmobile"}).status_code == 404
    c.post(f"/sessions/{sid}/vote/b", json={"option": names[0]})

    api.SESSIONS.clear()                              # simulate a restart: reload from SQLite
    st = c.get(f"/sessions/{sid}/state").json()
    assert st["winner"] == names[0] and "812" not in json.dumps(st)


def test_yes_to_private_compromise_relaxes_only_my_limit_and_reruns():
    s = family()
    engine.run(s)
    assert s.threads["mom"][-1]["replies"] == ["Yes, I'm open to it", "Keep looking"]
    engine.private_message(s, "mom", "Yes, I'm open to it")
    assert s.private["mom"]["max_monthly"] == 733
    assert s.top[0]["fits_all"] and "for everyone" in s.group[-1]["text"]
    assert "Mom" not in s.group[-1]["text"]


def test_keep_looking_keeps_limit():
    s = family()
    engine.run(s)
    engine.private_message(s, "mom", "Keep looking")
    assert s.private["mom"]["max_monthly"] == 650 and len(s.group) == 1


def test_bool_question_takes_yes_no():
    s = family()
    s.add_member("kid", "Kid")
    engine.private_message(s, "kid", "I can do $500 a month and need 5 seats")
    assert s.threads["kid"][-1]["replies"] == ["Yes", "No"]
    engine.private_message(s, "kid", "No")
    assert s.private["kid"]["needs_awd"] is False
    assert "everything I need" in s.threads["kid"][-1]["text"]
