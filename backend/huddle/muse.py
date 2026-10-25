"""Meta Model API clients (Muse Spark, Muse Image, Muse Voice Transcribe) plus offline mocks.

Docs: https://dev.meta.ai/docs/overview, /docs/tool-calling, /docs/speech-to-text, /docs/image-generation.
Base URL https://api.meta.ai/v1, `Authorization: Bearer $MODEL_API_KEY`, OpenAI-compatible request shapes.
"""
import base64
import json
import os
import re

import httpx

BASE = "https://api.meta.ai/v1"
KEY = os.environ.get("MODEL_API_KEY")
MODEL = os.environ.get("MUSE_SPARK_MODEL", "muse-spark-1.3")

JSON_TYPES = {"money": "number", "int": "integer", "bool": "boolean", "weight": "integer"}

EXPLAIN_SYSTEM = (
    "You are Muse, helping a group decide something together. "
    "Rewrite DRAFT into 2-4 short, friendly, plain-language sentences that explain the trade-offs in FACTS. "
    "Define any jargon (residual, money factor, equity) in everyday words. "
    "Use only numbers that appear in FACTS. Never guess anyone's budget or say who wants what."
)
EXTRACT_SYSTEM = (
    "You are Muse, privately helping one person state their constraints. "
    "Call record_constraints with only what the user actually said. Leave out anything not stated."
)
ADVISE_SYSTEM = (
    "You are Muse, watching prices for a group that is planning a purchase or booking. "
    "From FACTS (the item, its price history, the typical range, and how long until it's needed), decide whether "
    "the group should book now, wait, or keep watching, and call record_advice. "
    "headline: under 60 characters, names the item and the change in dollars. "
    "reason: one or two plain sentences using only numbers from FACTS. Never invent a forecast you can't support."
)
TRADEOFF_SYSTEM = (
    "You are Muse, helping a group compare options. For each option in FACTS, write one short trade-off "
    "(under 70 characters) that says what's good and what's the catch, using only facts given. "
    "Call record_tradeoffs with one entry per option id."
)
ANSWER_SYSTEM = (
    "You are Muse, the planner inside a group chat. Answer QUESTION in 1-3 short, friendly sentences using only "
    "PLAN (live search results and price watches). If PLAN doesn't cover it, say what you'd search for next."
)

ADVICE_TOOL = {"type": "function", "function": {
    "name": "record_advice",
    "description": "Record whether the group should act on this price now.",
    "parameters": {"type": "object", "required": ["verdict", "headline", "reason"], "properties": {
        "verdict": {"type": "string", "enum": ["book", "wait", "watch"]},
        "headline": {"type": "string"},
        "reason": {"type": "string"},
    }},
}}
TRADEOFF_TOOL = {"type": "function", "function": {
    "name": "record_tradeoffs",
    "description": "Record one short trade-off per option.",
    "parameters": {"type": "object", "required": ["tradeoffs"], "properties": {"tradeoffs": {
        "type": "array", "items": {"type": "object", "required": ["id", "text"],
                                   "properties": {"id": {"type": "string"}, "text": {"type": "string"}}},
    }}},
}}
SELECT_SYSTEM = (
    "You are Muse, choosing the research and the Google Drive files for one group plan. "
    "Call select_outputs once. Engines: google, google_flights, google_hotels, google_maps, google_shopping. "
    "Roles: budget, daily, places, comparison, market, dealer, decision, showtimes, evening, outing, shopping, overview. "
    "Match the plan. A movie night is not a flight search. A hike is not a car lease. A grocery list is one shopping sheet. "
    "Flight queries must look like 'AUS → HND, Mar 26 – Apr 4, 4 adults'. "
    "Hotel queries must look like 'Shinjuku, Mar 26 – 30, 2 rooms'. "
    "Do not invent prices, dates, or airports that are not in the plan."
)
SELECT_TOOL = {"type": "function", "function": {
    "name": "select_outputs",
    "description": "Choose the SerpAPI searches and the Sheets and Docs for this plan.",
    "parameters": {"type": "object", "properties": {
        "calls": {"type": "array", "items": {"type": "object", "properties": {
            "engine": {"type": "string"}, "query": {"type": "string"},
            "params": {"type": "object"},
        }, "required": ["engine", "query"]}},
        "files": {"type": "array", "items": {"type": "object", "properties": {
            "role": {"type": "string"}, "name": {"type": "string"},
        }, "required": ["role"]}},
    }, "required": ["calls", "files"]},
}}


def _schema_tool(fields):
    props = {}
    for f in fields:
        props[f["key"]] = {"type": JSON_TYPES[f["type"]], "description": f["label"]}
        if f["type"] == "weight":
            props[f["key"]] |= {"minimum": 0, "maximum": 5}
    return {"type": "function", "function": {
        "name": "record_constraints",
        "description": "Record the user's stated constraints and preferences.",
        "parameters": {"type": "object", "properties": props},
    }}


class Muse:
    def __init__(self, key):
        self.http = httpx.Client(base_url=BASE, headers={"Authorization": f"Bearer {key}"}, timeout=60)

    def _chat(self, messages, **extra):
        r = self.http.post("/chat/completions", json={"model": MODEL, "messages": messages, **extra})
        r.raise_for_status()
        return r.json()["choices"][0]["message"]

    def extract(self, fields, text):
        msg = self._chat(
            [{"role": "system", "content": EXTRACT_SYSTEM}, {"role": "user", "content": text}],
            tools=[_schema_tool(fields)], tool_choice="auto",
        )
        calls = msg.get("tool_calls") or []
        return json.loads(calls[0]["function"]["arguments"]) if calls else {}

    def explain(self, facts, draft):
        msg = self._chat([
            {"role": "system", "content": EXPLAIN_SYSTEM},
            {"role": "user", "content": f"FACTS:\n{json.dumps(facts)}\n\nDRAFT:\n{draft}"},
        ])
        return msg.get("content") or draft

    def _tool(self, system, facts, tool):
        msg = self._chat(
            [{"role": "system", "content": system}, {"role": "user", "content": f"FACTS:\n{json.dumps(facts)}"}],
            tools=[tool], tool_choice={"type": "function", "function": {"name": tool["function"]["name"]}},
        )
        calls = msg.get("tool_calls") or []
        if not calls:
            raise ValueError("Muse didn't call the tool")
        return json.loads(calls[0]["function"]["arguments"])

    def advise(self, facts):
        out = self._tool(ADVISE_SYSTEM, facts, ADVICE_TOOL)
        if out.get("verdict") not in ("book", "wait", "watch"):
            raise ValueError(f"unexpected verdict {out.get('verdict')!r}")
        return {k: out[k] for k in ("verdict", "headline", "reason")}

    def tradeoffs(self, options):
        out = self._tool(TRADEOFF_SYSTEM, options, TRADEOFF_TOOL)
        return {t["id"]: t["text"] for t in out.get("tradeoffs", []) if t.get("id") and t.get("text")}

    def answer(self, question, plan):
        msg = self._chat([
            {"role": "system", "content": ANSWER_SYSTEM},
            {"role": "user", "content": f"PLAN:\n{json.dumps(plan)}\n\nQUESTION:\n{question}"},
        ])
        return msg.get("content") or ""

    def select_outputs(self, plan):
        """Muse picks the SerpAPI searches and Drive files for this plan. Raises if it declines."""
        msg = self._chat(
            [{"role": "system", "content": SELECT_SYSTEM},
             {"role": "user", "content": json.dumps(plan, default=str)[:12000]}],
            tools=[SELECT_TOOL],
            tool_choice={"type": "function", "function": {"name": "select_outputs"}},
        )
        calls = msg.get("tool_calls") or []
        if not calls:
            raise ValueError("Muse did not choose any files")
        return json.loads(calls[0]["function"]["arguments"])

    def transcribe(self, wav: bytes) -> str:
        # WAV only: mono, 16-bit PCM, 16 or 24 kHz, <=10 min.
        req = {"mode": "PUSH_TO_TALK", "model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV"}
        r = self.http.post("/asr/transcribe", files={
            "request": (None, json.dumps(req), "application/json"),
            "audio": ("note.wav", wav, "audio/wav"),
        })
        r.raise_for_status()
        return r.json()["transcript"]

    def image(self, prompt) -> bytes:
        r = self.http.post("/images/generations", json={"model": "muse-image-1.0", "prompt": prompt, "n": 1})
        r.raise_for_status()
        return base64.b64decode(r.json()["data"][0]["b64_json"])


class MockMuse:
    """Offline stand-in: keyword extraction, explanations return the deterministic draft."""

    def extract(self, fields, text):
        low, out = text.lower(), {}
        for f in fields:
            if f["type"] == "money":
                m = re.search(r"\$\s?([\d,]+)", text)
                if m:
                    out[f["key"]] = float(m.group(1).replace(",", ""))
            elif f["type"] == "int":
                m = re.search(rf"(\d+)\s*{f['unit']}", low)
                if m:
                    out[f["key"]] = int(m.group(1))
            elif any(k in low for k in f.get("keywords", [])):
                out[f["key"]] = True if f["type"] == "bool" else 5
        return out

    def explain(self, facts, draft):
        return draft

    def advise(self, facts):
        """Rule of thumb: a drop to (near) the lowest price seen means book; a rise close to the date means book."""
        name, unit = facts["item"], facts.get("unit", "")
        old, new, low = facts["previous"], facts["current"], facts["lowest_seen"]
        diff = new - old
        days = facts.get("days_until")
        each = f" {unit}" if unit else ""
        if diff < 0:
            headline = f"{name} dropped ${abs(diff):,.0f} to ${new:,.0f}"
            if new <= low * 1.01:
                return {"verdict": "book", "headline": headline,
                        "reason": f"That's the lowest price seen so far (${new:,.0f}{each}). Prices this low rarely last."}
            return {"verdict": "watch", "headline": headline,
                    "reason": f"Cheaper, but still above the low of ${low:,.0f}{each}. Worth waiting a few days."}
        headline = f"{name} rose ${diff:,.0f} to ${new:,.0f}"
        if days is not None and days < 45:
            return {"verdict": "book", "headline": headline,
                    "reason": f"Only {days} days to go, and prices usually climb from here. Book soon."}
        return {"verdict": "wait", "headline": headline,
                "reason": f"Still {days} days out. It was ${low:,.0f}{each} before, so it may come back down."
                if days is not None else f"It was ${low:,.0f}{each} before, so it may come back down."}

    def tradeoffs(self, options):
        return {o["id"]: o.get("draft", "") for o in options}

    def answer(self, question, plan):
        demo = "(Demo: add MODEL_API_KEY for Muse's real answer.)"
        watching = [w for w in plan.get("watches", []) if w.get("current")]
        if not watching:
            return f"{demo} I don't have live prices for that yet."
        words = question.lower()
        topic = [w for w in watching if (w.get("category") == "flights" and "flight" in words)
                 or (w.get("category") == "stays" and any(k in words for k in ("hotel", "stay")))] or watching
        advised = [w for w in topic if w.get("advice")]
        if advised:
            w = max(advised, key=lambda w: w["advice"]["at"])
            verdict = {"book": "Book now", "wait": "Wait", "watch": "Keep watching"}[w["advice"]["verdict"]]
            return f"{demo} {w['advice']['headline']}. My call: {verdict}. {w['advice']['reason']}"
        w = min(topic, key=lambda w: w["current"])
        return f"{demo} I'm watching {len(topic)} prices. Lowest: {w['label']} at ${w['current']:,.0f} {w.get('unit', '')}.".rstrip()

    def select_outputs(self, plan):
        from .workspace import heuristic_outputs
        return heuristic_outputs(plan)

    def transcribe(self, wav):
        return "We need 7 seats and I'd like to keep it under $650 a month."

    def image(self, prompt):
        # 1x1 transparent PNG
        return base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")


muse = Muse(KEY) if KEY else MockMuse()
LIVE = bool(KEY)
