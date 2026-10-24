"""HTTP API for the iOS app. Run: uv run --env-file .env uvicorn huddle.api:app --reload

ponytail: in-memory sessions and no auth (member_id is trusted); Supabase + auth come in milestone 4.
"""
import uuid

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from . import engine
from .templates import TEMPLATES

app = FastAPI(title="Huddle")
SESSIONS: dict[str, engine.Session] = {}


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


def _get(sid) -> engine.Session:
    if sid not in SESSIONS:
        raise HTTPException(404, "no such session")
    return SESSIONS[sid]


def _member(s, mid):
    if mid not in s.members:
        raise HTTPException(404, "no such member")


@app.post("/sessions")
def create(body: NewSession):
    if body.template not in TEMPLATES:
        raise HTTPException(400, f"unknown template; choose from {list(TEMPLATES)}")
    s = engine.Session(TEMPLATES[body.template], {"location": "Austin, TX", **body.context})
    for m in body.members:
        s.add_member(m.id, m.name)
    SESSIONS[s.id] = s
    return info(s.id)


@app.get("/sessions/{sid}")
def info(sid: str):
    s = _get(sid)
    return {"id": s.id, "template": s.template["id"], "title": s.template["title"],
            "context": s.context, "members": s.members}


@app.post("/sessions/{sid}/join")
def join(sid: str, body: Join):
    """The session id doubles as the invite code."""
    s = _get(sid)
    mid = uuid.uuid4().hex[:8]
    s.add_member(mid, body.name.strip()[:40] or "Guest")
    return {"member_id": mid, **info(sid)}


@app.post("/sessions/{sid}/group/{mid}")
def say(sid: str, mid: str, body: Text):
    s = _get(sid)
    _member(s, mid)
    s.post_group(body.text, author=mid)
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
    try:
        engine.private_message(s, mid, body.text)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return s.threads[mid]


@app.post("/sessions/{sid}/private/{mid}/explain/{option}")
def explain(sid: str, mid: str, option: str):
    s = _get(sid)
    _member(s, mid)
    try:
        engine.explain_option(s, mid, option)
    except KeyError:
        raise HTTPException(404, "option not in the current results")
    return s.threads[mid]


@app.post("/sessions/{sid}/run")
def run(sid: str):
    s = _get(sid)
    engine.run(s)
    return s.group
