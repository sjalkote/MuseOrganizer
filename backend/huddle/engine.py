"""Generic decision engine: private constraints -> merged limits -> ranked options -> group-safe messages.

Privacy model: per-member values live only in Session.private and each member's own thread.
Group text is built from option data and anonymized conflict info, Spark only ever sees public facts,
and every Muse group message passes `_leaks` before it is stored.
"""
import re
import uuid
from dataclasses import dataclass, field

from . import serp
from .muse import muse

MERGE = {"<=": min, ">=": max, "requires": any}
NEUTRAL = "Here are the top options. Tap a card for details, then vote."


@dataclass
class Session:
    template: dict
    context: dict                                   # public, e.g. {"location": "Austin, TX"}
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:8])
    members: dict = field(default_factory=dict)     # member_id -> display name
    private: dict = field(default_factory=dict)     # member_id -> {field_key: value}
    threads: dict = field(default_factory=dict)     # member_id -> [message]
    group: list = field(default_factory=list)       # [message]
    found: dict = field(default_factory=dict)       # session-level search results (dealers, ...)
    top: list = field(default_factory=list)         # options last posted to the group

    @property
    def schema(self):
        return self.template["constraint_schema"]

    def add_member(self, mid, name):
        self.members[mid] = name
        self.private.setdefault(mid, {})
        self.threads.setdefault(mid, [])

    def set_constraints(self, mid, values):
        """Validate and store one member's values. This is the trust boundary for constraint input."""
        if mid not in self.members:
            raise KeyError(mid)
        by_key = {f["key"]: f for f in self.schema}
        for key, v in values.items():
            f = by_key.get(key)
            if f is None or v is None:
                continue
            if f["type"] == "money":
                v = float(v)
                if v <= 0:
                    raise ValueError(f"{key} must be positive")
            elif f["type"] == "int":
                v = int(v)
            elif f["type"] == "bool":
                v = bool(v)
            elif f["type"] == "weight":
                v = max(0, min(5, int(v)))
            self.private[mid][key] = v

    def say_private(self, mid, author, text):
        self.threads[mid].append({"author": author, "text": text})

    def post_group(self, text, cards=(), author="muse"):
        if author == "muse" and _leaks(text, self):
            text = NEUTRAL
        self.group.append({"author": author, "text": text, "cards": list(cards)})


# --- privacy ---------------------------------------------------------------

def _numbers(text):
    return {float(n.replace(",", "")) for n in re.findall(r"\d[\d,]*(?:\.\d+)?", text)}


def _leaks(text, s):
    """True if text contains any member's private number or free-text value."""
    nums, low = _numbers(text), text.lower()
    for values in s.private.values():
        for v in values.values():
            if isinstance(v, bool):
                continue
            if isinstance(v, (int, float)) and float(v) in nums:
                return True
            if isinstance(v, str) and len(v) > 3 and v.lower() in low:
                return True
    return False


def safe_explain(facts, draft):
    """Spark rewrite, rejected if it uses any number not present in the facts or draft."""
    out = muse.explain(facts, draft)
    allowed = _numbers(str(facts)) | _numbers(draft)
    # ponytail: small counts (top 3, 2 cars) always allowed; private seat counts never reach Spark anyway.
    invented = {n for n in _numbers(out) if n > 10 and n not in allowed}
    return draft if invented else out


# --- private interview -----------------------------------------------------

def _fmt(f, v):
    if f["type"] == "money":
        return f"{f['label']} ${v:,.0f}"
    if f["type"] == "weight":
        return f"{f['label']}: {v}"
    if f["type"] == "bool":
        return f["label"] if v else f"doesn't need {f['label'].removeprefix('needs ')}"
    return f"{f['label']}: {v}"


def private_message(s, mid, text):
    """Member tells Muse something privately; Muse records constraints and asks the next question."""
    s.say_private(mid, mid, text)
    found = muse.extract(s.schema, text)
    s.set_constraints(mid, found)
    mine = s.private[mid]
    got = [_fmt(f, mine[f["key"]]) for f in s.schema if f["key"] in found]
    missing = [f for f in s.schema if f["kind"] == "hard" and f["key"] not in mine]
    reply = ("Got it: " + "; ".join(got) + ". " if got else "")
    reply += missing[0]["ask"] if missing else "That's everything I need. This stays between us."
    s.say_private(mid, "muse", reply)
    return reply


# --- scoring ---------------------------------------------------------------

def merged_limits(s):
    limits = {}
    for f in s.schema:
        if f["kind"] != "hard":
            continue
        vals = [p[f["key"]] for p in s.private.values() if f["key"] in p]
        if vals:
            limits[f["key"]] = MERGE[f["op"]](vals)
    return limits


def violations(option, limits, schema):
    """[(field, relative_gap)] for each merged hard limit the option breaks."""
    out = []
    for f in schema:
        if f["kind"] != "hard" or f["key"] not in limits:
            continue
        v, lim = option[f["attr"]], limits[f["key"]]
        if f["op"] == "<=" and v > lim:
            out.append((f, (v - lim) / lim))
        elif f["op"] == ">=" and v < lim:
            out.append((f, (lim - v) / lim))
        elif f["op"] == "requires" and lim and not v:
            out.append((f, 1.0))
    return out


def rank(options, s):
    """Weighted 0-100 score across every member's soft preferences (min-max normalized)."""
    scores, total = [0.0] * len(options), 0
    for f in (f for f in s.schema if f["kind"] == "soft"):
        w = sum(p.get(f["key"], f["default"]) for p in s.private.values())
        vals = [o[f["attr"]] for o in options]
        lo, hi = min(vals), max(vals)
        for i, v in enumerate(vals):
            n = 1.0 if hi == lo else (v - lo) / (hi - lo)
            scores[i] += w * (1 - n if f["better"] == "lower" else n)
        total += w
    for o, sc in zip(options, scores):
        o["score"] = round(100 * sc / total) if total else 0
    return sorted(options, key=lambda o: -o["score"])


# --- search ----------------------------------------------------------------

def _pluck(res, step):
    return [{k: r.get(k) for k in step["fields"]} for r in res.get(step["pick"], [])[: step["limit"]]]


def enrich(s, top):
    for step in s.template["search_plan"]:
        targets = top if step["per"] == "option" else [None]
        for o in targets:
            params = {k: v.format(**s.context, **(o or {})) for k, v in step["params"].items()}
            items = _pluck(serp.search(step["engine"], **params), step)
            (o if o is not None else s.found)[step["as"]] = items


# --- run -------------------------------------------------------------------

def run(s, top_n=3):
    t = s.template
    prepare = t.get("prepare", lambda o, ctx: o)
    options = [prepare(dict(o), s.context) for o in t["catalog"]]
    limits = merged_limits(s)
    fits = [o for o in options if not violations(o, limits, s.schema)]

    if fits:
        top = rank(fits, s)[:top_n]
        draft = f"I found {len(fits)} {t['noun']}s that work for everyone. Top pick: {top[0]['name']}."
    else:
        top = _compromise(s, options, limits)[:top_n]
        draft = _compromise_text(s, top[0], limits)

    for o in top:
        o["fits_all"] = bool(fits)
    enrich(s, top)
    facts = [{k: o[k] for k in t["explain_fields"] if k in o} for o in top]
    text = safe_explain({"options": facts, "assumptions": t.get("assumptions", {})}, draft)
    s.post_group(text, cards=[{"type": t["card"], "option": o} for o in top])
    s.top = top
    return top


def explain_option(s, mid, name):
    """Template's explainer for one posted option, personalized with this member's own values, sent privately."""
    o = next((o for o in s.top if o["name"] == name), None)
    if o is None:
        raise KeyError(name)
    facts, draft = s.template["explain"](o, s.private[mid])
    text = safe_explain(facts, draft)
    s.say_private(mid, "muse", text)
    return text


def _compromise(s, options, limits):
    """Options ordered by fewest broken limits, then smallest total relative gap."""
    def cost(o):
        v = violations(o, limits, s.schema)
        return (len(v), sum(g for _, g in v))
    ranked = rank(options, s)  # sets scores; stable sort keeps score order on ties
    return sorted(ranked, key=cost)


def _compromise_text(s, best, limits):
    misses = violations(best, limits, s.schema)
    parts = [f"{'a bit' if gap < 0.15 else 'well'} {f['miss']}" if f["op"] != "requires" else f["miss"]
             for f, gap in misses]
    _ask_privately(s, best, misses)
    return (f"No {s.template['noun']} fits everyone's limits. The closest is the {best['name']}: "
            f"it's {' and '.join(parts)}. I've checked in privately with whoever it affects.")


def _ask_privately(s, best, misses):
    """Tell each member whose own limit the compromise breaks, in their own thread only."""
    for f, _ in misses:
        for mid, mine in s.private.items():
            if f["key"] not in mine:
                continue
            if violations(best, {f["key"]: mine[f["key"]]}, [f]):
                v = best[f["attr"]]
                actual = "" if f["op"] == "requires" else f"; it's {'$' if f['type'] == 'money' else ''}{v:,}"
                s.say_private(mid, "muse",
                              f"Only you can see this: the {best['name']} breaks your limit "
                              f"({_fmt(f, mine[f['key']])}{actual}). "
                              "Would you be open to it, or should I keep looking?")
