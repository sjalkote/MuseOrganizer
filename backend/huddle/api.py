"""HTTP API for the iOS app. Run: uv run --env-file .env uvicorn huddle.api:app --reload

ponytail: in-memory sessions and no auth (member_id is trusted); Supabase + auth come in milestone 4.
"""
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
    members: list[Member]


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
    s = engine.Session(TEMPLATES[body.template], body.context)
    for m in body.members:
        s.add_member(m.id, m.name)
    SESSIONS[s.id] = s
    return {"id": s.id, "members": s.members}


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


@app.post("/sessions/{sid}/run")
def run(sid: str):
    s = _get(sid)
    engine.run(s)
    return s.group
