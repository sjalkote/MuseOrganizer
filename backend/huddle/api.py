"""HTTP API for the iOS app.
Run: uv run --env-file .env uvicorn huddle.api:app --reload --timeout-graceful-shutdown 1
(the timeout stops open event streams from blocking reloads)

Sessions persist in SQLite (HUDDLE_DB, default huddle.db). Clients watch GET /sessions/{sid}/events,
a Server-Sent Events stream that only carries a version number, never message content, and refetch
what they are allowed to see. ponytail: no auth (member_id is trusted); add signed member tokens before
this leaves the demo.
"""
import asyncio
import contextlib
import dataclasses
import time
import json
import os
import sqlite3
import threading
import uuid

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse, StreamingResponse
from pydantic import BaseModel, Field

from . import board, engine, google, lookup, serp, tabs, watch, workspace
from . import muse as muse_mod
from .templates import TEMPLATES

# Seconds between price-watch sweeps; 0 turns the background sweep off (the app can still ask for a check).
WATCH_INTERVAL = float(os.environ.get("HUDDLE_WATCH_INTERVAL", "21600"))


async def _sweep():
    while True:
        await asyncio.sleep(WATCH_INTERVAL)
        await asyncio.to_thread(watch.check_all)


@contextlib.asynccontextmanager
async def lifespan(_app):
    task = asyncio.create_task(_sweep()) if WATCH_INTERVAL > 0 else None
    yield
    if task:
        task.cancel()


app = FastAPI(title="Huddle", lifespan=lifespan)
DB = os.environ.get("HUDDLE_DB", "huddle.db")
SESSIONS: dict[str, engine.Session] = {}
# ponytail: one global lock around every mutation; per-session locks if many groups get busy at once.
LOCK = threading.Lock()

with sqlite3.connect(DB) as _c:
    _c.execute("create table if not exists sessions (id text primary key, data text not null)")
    _c.execute("create table if not exists google_tokens (account text primary key, refresh_token text not null)")


def _save(s):
    s.version += 1
    d = {f.name: getattr(s, f.name) for f in dataclasses.fields(s) if f.name != "template"}
    d["template"] = s.template["id"]
    with sqlite3.connect(DB) as c:
        c.execute("insert or replace into sessions values (?, ?)", (s.id, json.dumps(d)))


def _get(sid) -> engine.Session:
    if sid not in SESSIONS:
        with sqlite3.connect(DB) as c:
            row = c.execute("select data from sessions where id = ?", (sid,)).fetchone()
        if not row:
            raise HTTPException(404, "no such session")
        d = json.loads(row[0])
        SESSIONS[sid] = engine.Session(template=TEMPLATES[d.pop("template")], **d)
    return SESSIONS[sid]


def _member(s, mid):
    if mid not in s.members:
        raise HTTPException(404, "no such member")


class Member(BaseModel):
    id: str
    name: str


class NewSession(BaseModel):
    template: str
    context: dict[str, str] = {}
    members: list[Member] = []


class Join(BaseModel):
    name: str


class Text(BaseModel):
    text: str


class Vote(BaseModel):
    option: str


@app.post("/sessions")
def create(body: NewSession):
    if body.template not in TEMPLATES:
        raise HTTPException(400, f"unknown template; choose from {list(TEMPLATES)}")
    s = engine.Session(TEMPLATES[body.template], {"location": "Austin, TX", **body.context})
    for m in body.members:
        s.add_member(m.id, m.name)
    with LOCK:
        SESSIONS[s.id] = s
        _save(s)
    return info(s.id)


@app.get("/sessions/{sid}")
def info(sid: str):
    s = _get(sid)
    return {"id": s.id, "template": s.template["id"], "title": s.template["title"],
            "context": s.context, "members": s.members}


@app.get("/sessions/{sid}/state")
def state(sid: str, member: str = ""):
    """Everything the group view needs in one call. Vote counts are public; who voted for what is not."""
    s = _get(sid)
    return {**info(sid), "version": s.version, "group": s.group, "tally": engine.tally(s),
            "voted": [s.members[m] for m in s.votes],
            # Who has talked to Muse privately (never what they said), so the group knows when to search.
            "shared": [s.members[m] for m, v in s.private.items() if v], "my_vote": s.votes.get(member), "winner": s.winner}


@app.get("/sessions/{sid}/events")
async def events(sid: str, request: Request):
    _get(sid)

    async def stream():
        seen, idle = -1, 0
        while not await request.is_disconnected():
            v = _get(sid).version
            if v != seen:
                seen, idle = v, 0
                yield f"data: {v}\n\n"
            elif (idle := idle + 1) % 60 == 0:
                yield ": ping\n\n"  # keeps idle connections from timing out
            # ponytail: 250 ms version check per client; push via a pub/sub if clients grow past a demo.
            await asyncio.sleep(0.25)

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.post("/sessions/{sid}/join")
def join(sid: str, body: Join):
    """The session id doubles as the invite code."""
    s = _get(sid)
    mid = uuid.uuid4().hex[:8]
    with LOCK:
        s.add_member(mid, body.name.strip()[:40] or "Guest")
        _save(s)
    return {"member_id": mid, **info(sid)}


@app.post("/sessions/{sid}/group/{mid}")
def say(sid: str, mid: str, body: Text):
    s = _get(sid)
    _member(s, mid)
    with LOCK:
        s.post_group(body.text, author=mid)
        _save(s)
    return s.group


@app.get("/sessions/{sid}/group")
def group(sid: str):
    return _get(sid).group


@app.get("/sessions/{sid}/private/{mid}")
def thread(sid: str, mid: str):
    s = _get(sid)
    _member(s, mid)
    return s.threads[mid]


@app.post("/sessions/{sid}/private/{mid}")
def tell(sid: str, mid: str, body: Text):
    s = _get(sid)
    _member(s, mid)
    with LOCK:
        try:
            engine.private_message(s, mid, body.text)
        except ValueError as e:
            raise HTTPException(400, str(e))
        _save(s)
    return s.threads[mid]


@app.post("/sessions/{sid}/private/{mid}/explain/{option}")
def explain(sid: str, mid: str, option: str):
    s = _get(sid)
    _member(s, mid)
    with LOCK:
        try:
            engine.explain_option(s, mid, option)
        except KeyError:
            raise HTTPException(404, "option not in the current results")
        _save(s)
    return s.threads[mid]


@app.post("/sessions/{sid}/run")
def run(sid: str):
    s = _get(sid)
    with LOCK:
        engine.run(s)
        _save(s)
    return s.group


@app.post("/sessions/{sid}/vote/{mid}")
def vote(sid: str, mid: str, body: Vote):
    s = _get(sid)
    _member(s, mid)
    with LOCK:
        try:
            engine.vote(s, mid, body.option)
        except KeyError:
            raise HTTPException(404, "option not in the current results")
        except ValueError as e:
            raise HTTPException(409, str(e))
        _save(s)
    return state(sid, mid)


# MARK: - Plan folders (docs/GOOGLE_WORKSPACE_SETUP.md)
# ponytail: one Google account per backend ("default"); key tokens by user once the app has accounts.


def _refresh_token():
    with sqlite3.connect(DB) as c:
        row = c.execute("select refresh_token from google_tokens where account = 'default'").fetchone()
    return row[0] if row else None


def _store_token(code, redirect_uri=google.REDIRECT_URI):
    if not google.configured():
        raise HTTPException(503, "set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET on the backend first")
    try:
        token = google.exchange(code, redirect_uri)
    except (httpx.HTTPError, ValueError) as e:
        raise HTTPException(400, f"Google sign-in failed: {e}")
    with sqlite3.connect(DB) as c:
        c.execute("insert or replace into google_tokens values ('default', ?)", (token,))


class BuildCall(BaseModel):
    id: str
    engine: str
    query: str
    params: dict[str, str] = {}


class BuildFile(BaseModel):
    id: str
    name: str
    kind: str
    summary: str = ""
    sources: list[str] = []
    content: dict | None = None  # {columns, rows, footer} or {blocks: [{type, text}]}; used when we can't research it


class BuildPlan(BaseModel):
    folderName: str = ""
    name: str = ""
    kind: str = ""
    members: list[str] = []
    decisions: list[dict] = []
    options: list[dict] = []
    itinerary: list[dict] = []
    notes: str = ""
    messages: list[str] = []
    context: dict[str, str] = {}
    calls: list[BuildCall] = []
    files: list[BuildFile] = []


class AuthCode(BaseModel):
    serverAuthCode: str


def _live_required():
    """A live folder build calls SerpAPI. Muse is optional until docs/RESTORE_MUSE.md. Pytest sets HUDDLE_OFFLINE=1."""
    if os.environ.get("HUDDLE_OFFLINE") == "1":
        return
    if not os.environ.get("SERPAPI_API_KEY"):
        raise HTTPException(503, "This build needs live SerpAPI. Missing SERPAPI_API_KEY.")


@app.post("/plans/{pid}/workspace", status_code=202)
def build_workspace(pid: str, body: BuildPlan):
    """Start building the plan's folder. The local chooser picks files unless Muse is enabled.

    Google Drive is optional. A connected account writes Sheets and Docs; otherwise the
    same files land locally and the app shows them.
    """
    _live_required()
    token = _refresh_token() if google.configured() else None
    if token:
        make = lambda: google.Drive(token)
        mode = "google"
    else:
        make, mode = workspace.MockDrive, "local"
    snap = body.model_dump()
    snap["folderName"] = body.folderName or body.name or "Plan"
    b = workspace.start({"planId": pid, **snap}, make, on_done=lambda plan, files: _remember_budget(pid, plan, files))
    return {"buildId": b.id, "mode": mode}


def _remember_budget(pid, plan, files):
    """Point the plan's price watches at the Budget Tracker this build wrote."""
    sheet = next((f for f in files if f["name"].lower() == "budget tracker" and f.get("url")), None)
    if sheet:
        cap = plan.get("context", {}).get("budgetPerPerson")
        watch.register_budget(pid, sheet["url"], workspace.travelers(plan), float(cap) if cap else None)


@app.get("/builds/{bid}/events")
async def build_events(bid: str, request: Request):
    """Replays the build's events from the start, then follows it until it ends."""
    b = workspace.BUILDS.get(bid)
    if not b:
        raise HTTPException(404, "no such build")

    async def stream():
        sent = 0
        while not await request.is_disconnected():
            done = b.done
            for kind, data in b.events[sent:]:
                sent += 1
                yield f"event: {kind}\ndata: {json.dumps(data)}\n\n"
            if done and sent == len(b.events):
                return
            await asyncio.sleep(0.1)

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.delete("/builds/{bid}")
def cancel_build(bid: str):
    """Stop a build; anything it already wrote to Drive is deleted."""
    b = workspace.BUILDS.get(bid)
    if not b:
        raise HTTPException(404, "no such build")
    b.cancelled = True
    return {"cancelled": not b.done}


@app.get("/auth/google/status")
def google_status():
    return {"mode": "google" if google.configured() else "mock", "configured": google.configured(),
            "connected": bool(_refresh_token())}


@app.get("/auth/google/start")
def google_start():
    """Browser sign-in for the demo; the app can instead send its serverAuthCode to /auth/google/code."""
    if not google.configured():
        raise HTTPException(503, "set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET on the backend first")
    return RedirectResponse(google.consent_url())


@app.get("/auth/google/callback")
def google_callback(code: str = "", error: str = ""):
    if error or not code:
        raise HTTPException(400, f"Google sign-in failed: {error or 'no code'}")
    _store_token(code)
    return HTMLResponse("<p>Google Drive is connected to Huddle. You can close this tab.</p>")


@app.post("/auth/google/code")
def google_code(body: AuthCode):
    _store_token(body.serverAuthCode, redirect_uri="")
    return google_status()


# MARK: - Live board and Muse price watch (huddle/board.py, huddle/watch.py)


class Flight(BaseModel):
    model_config = {"populate_by_name": True}
    from_: str = Field(alias="from")
    to: str
    depart: str
    return_: str = Field(alias="return")


class Stay(BaseModel):
    area: str
    checkIn: str
    checkOut: str
    rooms: int = 1


class Trip(BaseModel):
    travelers: int = 1
    budgetPerPerson: float | None = None
    flights: list[Flight] = []
    stays: list[Stay] = []
    activities: list[str] = []


class NewWatch(BaseModel):
    category: str
    label: str
    engine: str
    params: dict[str, str | int] = {}
    match: str = ""
    detail: str = ""
    unit: str = ""
    neededBy: str | None = None


class Question(BaseModel):
    question: str
    name: str = ""
    kind: str = ""


class PlanSetupIn(BaseModel):
    name: str = ""
    kind: str = ""
    request: str = ""
    notes: str = ""


@app.get("/status")
def status():
    """Which services are live. Anything not live runs on labeled demo data."""
    return {"muse": muse_mod.LIVE, "serpapi": serp.LIVE, "google": google.configured(), "watchInterval": WATCH_INTERVAL}


@app.post("/plans/{pid}/board")
def trip_board(pid: str, body: Trip):
    trip = body.model_dump(by_alias=True)
    trip["flights"] = [{"from": f["from"], "to": f["to"], "depart": f["depart"], "return": f["return"]} for f in trip["flights"]]
    try:
        return board.build(pid, trip)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"SerpApi search failed: {e}")


@app.get("/plans/{pid}/watches")
def plan_watches(pid: str):
    return {"watches": watch.for_plan(pid), "alerts": watch.alerts(plan_id=pid)[-20:]}


@app.post("/plans/{pid}/watches")
def add_watch(pid: str, body: NewWatch):
    found = watch.find(pid, body.engine, body.params, body.match)
    if found:
        return found
    try:
        seed = serp.search(body.engine, **body.params)
    except (httpx.HTTPError, KeyError) as e:
        raise HTTPException(400, f"can't search {body.engine}: {e}")
    return watch.create(pid, body.category, body.label, body.engine, body.params, match=body.match, detail=body.detail,
                        unit=body.unit, needed_by=body.neededBy, seed=seed)


@app.delete("/watches/{wid}")
def stop_watch(wid: str):
    watch.remove(wid)
    return {"removed": wid}


@app.post("/plans/{pid}/watches/check")
def check_now(pid: str):
    """Re-check every watch on the plan right away (the app's pull-to-refresh and background refresh)."""
    try:
        new = watch.check_plan(pid)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"SerpApi search failed: {e}")
    return {"alerts": new, "watches": watch.for_plan(pid)}


@app.get("/alerts")
def all_alerts(since: float = 0):
    """Alerts newer than `since` (unix seconds) across every plan; the app turns each into a notification."""
    return {"alerts": watch.alerts(since), "now": time.time()}


def _watch_summary(watches):
    return [{k: w[k] for k in ("category", "label", "detail", "unit", "current", "low", "high")} | {"advice": w["advice"]}
            for w in watches]


@app.post("/plans/setup")
def plan_setup(body: PlanSetupIn):
    """The tabs for this plan. Muse chooses them when it is on; the rules are the fallback."""
    facts = body.model_dump()
    raw = None
    if workspace.builds_use_muse():
        try:
            raw = muse_mod.muse.plan_setup(facts)
        except (httpx.HTTPError, ValueError, KeyError):
            raw = None
    setup = tabs.finalize(raw, facts)
    setup["live"] = bool(workspace.builds_use_muse() and muse_mod.LIVE)
    return setup


@app.post("/plans/{pid}/ask")
def ask(pid: str, body: Question):
    """A chat reply. Muse picks the module, SerpAPI fills it, and Muse writes from those results."""
    existing = watch.for_plan(pid)
    if lookup.is_empty(body.question):
        # A bare "@Muse": ask what they need instead of searching for the plan's name.
        return {"text": "I'm here! What should I look up: flights, places to stay, food, or prices?",
                "live": muse_mod.LIVE, "options": [], "list": None}
    if lookup.about_existing_watches(body.question, existing):
        return _answer_from_watches(body.question, existing)
    module, subject = None, None
    if workspace.builds_use_muse():
        try:
            choice = muse_mod.muse.choose_module({"question": body.question, "name": body.name, "kind": body.kind})
            module = choice.get("module")
            subject = lookup.grounded_subject(choice.get("subject", ""), body.question, body.name)
        except (httpx.HTTPError, ValueError, KeyError):
            module, subject = None, None
    try:
        found = lookup.answer(pid, body.question, name=body.name, kind=body.kind, module=module, subject=subject)
    except (httpx.HTTPError, RuntimeError, KeyError) as e:
        if existing:
            return _answer_from_watches(body.question, existing)
        raise HTTPException(502, f"SerpApi search failed: {e}")
    text = found["text"]
    if workspace.builds_use_muse():
        try:
            polished = muse_mod.muse.answer(body.question, {"search": found["facts"], "watches": _watch_summary(existing)})
            if polished:
                text = polished
        except (httpx.HTTPError, ValueError):
            pass
    text, listing = _with_list(text, found, body)
    return {"text": text, "live": found["live"], "options": found["options"], "list": listing}


def _answer_from_watches(question, existing):
    try:
        text = muse_mod.muse.answer(question, {"watches": _watch_summary(existing)})
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Muse didn't answer: {e}")
    return {"text": text, "live": muse_mod.LIVE, "options": [], "list": None}


def _with_list(text, found, body):
    """Say which tab the new rows belong on, in the reply itself."""
    options = found.get("options") or []
    if not options:
        return text, None
    blob = f"{body.name} {body.question} {body.kind}".lower()
    module = found.get("module")
    if module == "flights":
        listing = {"id": "flights", "title": "Flights", "kind": "options"}
    elif module == "price" and ("decision" in body.kind or "car" in blob):
        listing = {"id": "prices", "title": "Prices", "kind": "decision"}
    elif module == "price":
        listing = {"id": "prices", "title": "Prices", "kind": "options"}
    elif module == "places" and any(word in blob for word in ("movie", "theater", "showtime")):
        listing = {"id": "theaters", "title": "Theaters", "kind": "options"}
    elif module == "places" and any(word in blob for word in ("dinner", "restaurant", "food", "eat")):
        listing = {"id": "food", "title": "Food", "kind": "options"}
    elif module == "places":
        listing = {"id": "places", "title": "Places", "kind": "options"}
    else:
        return text, None
    titles = [option.get("title") or "" for option in options[:3] if option.get("title")]
    names = ", ".join(titles)
    count = len(options)
    # When Muse's reply already names the options, the lead just says where they went, so nothing repeats.
    named = any(title.lower().removesuffix(" (mock)") in text.lower() for title in titles)
    lead = f"I added {count} to {listing['title']}" + ("." if named or not names else f": {names}.")
    if "added" not in text.lower():
        text = f"{lead} {text}"
    return text, listing
