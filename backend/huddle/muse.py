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

    def transcribe(self, wav):
        return "We need 7 seats and I'd like to keep it under $650 a month."

    def image(self, prompt):
        # 1x1 transparent PNG
        return base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")


muse = Muse(KEY) if KEY else MockMuse()
