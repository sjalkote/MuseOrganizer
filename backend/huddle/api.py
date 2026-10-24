"""HTTP API for the iOS app.
Run: uv run --env-file .env uvicorn huddle.api:app --reload --timeout-graceful-shutdown 1
(the timeout stops open event streams from blocking reloads)

Sessions persist in SQLite (HUDDLE_DB, default huddle.db). Clients watch GET /sessions/{sid}/events,
a Server-Sent Events stream that only carries a version number, never message content, and refetch
what they are allowed to see. ponytail: no auth (member_id is trusted); add signed member tokens before
this leaves the demo.
"""
import asyncio
import dataclasses
import json
import os
import sqlite3
import threading
import uuid

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import engine
from .templates import TEMPLATES

app = FastAPI(title="Huddle")
DB = os.environ.get("HUDDLE_DB", "huddle.db")
SESSIONS: dict[str, engine.Session] = {}
# ponytail: one global lock around every mutation; per-session locks if many groups get busy at once.
LOCK = threading.Lock()

with sqlite3.connect(DB) as _c:
    _c.execute("create table if not exists sessions (id text primary key, data text not null)")


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
