"""Run a decision end to end from the terminal.

    uv run python -m huddle.cli              # family car, everyone fits
    uv run python -m huddle.cli --conflict   # tight budget -> anonymous compromise
"""
import argparse

from . import engine
from .templates import TEMPLATES

FAMILY = {
    "mom": ("Mom", "We need 7 seats for carpool. Gas matters, I commute a lot. I can do $800 a month."),
    "dad": ("Dad", "Keep it under $900/month. We need AWD for ski trips."),
    "teen": ("Teen", "Lots of cargo space for my friends' gear please!"),
}


def show(s):
    for mid, name in s.members.items():
        print(f"\n--- private: {name} (only {name} and Muse) ---")
        for m in s.threads[mid]:
            print(f"  {'Muse' if m['author'] == 'muse' else name}: {m['text']}")
    print("\n=== group chat ===")
    for m in s.group:
        print(f"  Muse: {m['text']}")
        for c in m["cards"]:
            o = c["option"]
            print(f"    [{o['name']}] ${o['msrp']:,} MSRP, ~${o['est_monthly']}/mo, {o['seats']} seats, "
                  f"{o['mpg']} mpg, score {o['score']}{'' if o['fits_all'] else ' (compromise)'}")
            f = o["finance"]
            print(f"      lease ${f['lease']['monthly']}/mo | finance ${f['finance']['monthly']}/mo | "
                  f"cash ${f['cash']['upfront']:,} | cheapest over {f['months']} mo: {f['best']}")
            for li in o.get("listings", [])[:1]:
                print(f"      listing: {li['title']}")
    for d in s.found.get("dealers", []):
        print(f"  dealer: {d['title']} - {d['address']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--conflict", action="store_true", help="give Mom a budget no 7-seater meets")
    ap.add_argument("--location", default="Austin, TX")
    args = ap.parse_args()

    s = engine.Session(TEMPLATES["car"], {"location": args.location})
    for mid, (name, text) in FAMILY.items():
        s.add_member(mid, name)
        if args.conflict and mid == "mom":
            text = text.replace("$800", "$650")
        engine.private_message(s, mid, text)
    top = engine.run(s)
    engine.explain_option(s, "mom", top[0]["name"])
    show(s)


if __name__ == "__main__":
    main()
