#!/usr/bin/env python3
"""Build data/bnb_roster.json from CHARACTER_SHEET.csv.

Each employee becomes a fighter built on one of the 8 base fighting styles (move sets in data/roster.json),
with their own name, role, look, stats and Surge name. Blank sheet cells fall back to neutral placeholders,
so the game always builds. Run:  python3 tools/gen_roster.py
"""
import csv, json, re, colorsys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STYLES = ["vex", "bastion", "sora", "ember", "mara", "lio", "tao", "kael"]
STYLE_NAMES = {"vex": "Precision", "bastion": "Heavy Hitter", "sora": "Kicks", "ember": "Grappler",
               "mara": "Boxing", "lio": "Acrobatic", "tao": "Kung Fu", "kael": "Muay Thai"}
# words in role / personality / fighting-style wish that point to a style (first match wins)
STYLE_HINTS = [
    (r"box|punch|quick|fast hands", "mara"), (r"kick|taekwondo|agile|energetic", "sora"),
    (r"wrestl|grab|throw|grapple|hr\b|people", "ember"), (r"heavy|tank|strong|calm|ceo|boss|founder", "bastion"),
    (r"kung|disciplin|focus|wise|senior", "tao"), (r"muay|elbow|knee|aggress|intense", "kael"),
    (r"dance|creative|design|acrobat|playful|fun", "lio"), (r"precise|analytic|engineer|developer|qa|data|manager|pm\b", "vex"),
]
BOSS = {"final": dict(hp=1.0, power=1.0), "mini": dict(hp=1.0, power=1.0), "bonus": dict(hp=1.0, power=1.0)}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def hue_color(i, n, s=0.6, v=0.95):
    r, g, b = colorsys.hsv_to_rgb((i / n + 0.72) % 1.0, s, v)
    return [round(r, 3), round(g, 3), round(b, 3)]


NAMED = {"red": [0.85, 0.2, 0.22], "blue": [0.2, 0.4, 0.95], "navy": [0.12, 0.16, 0.38], "green": [0.2, 0.7, 0.4],
         "purple": [0.55, 0.3, 0.9], "violet": [0.6, 0.35, 0.95], "pink": [1.0, 0.45, 0.7], "black": [0.12, 0.12, 0.14],
         "white": [0.92, 0.92, 0.94], "grey": [0.5, 0.52, 0.56], "gray": [0.5, 0.52, 0.56], "yellow": [1.0, 0.85, 0.25],
         "gold": [1.0, 0.78, 0.3], "orange": [1.0, 0.55, 0.15], "brown": [0.45, 0.3, 0.2], "teal": [0.15, 0.65, 0.65],
         "maroon": [0.45, 0.08, 0.12], "beige": [0.85, 0.78, 0.65], "cyan": [0.2, 0.85, 0.95]}


def color_of(text, default):
    for k, v in NAMED.items():
        if k in (text or "").lower(): return v
    return default


def pick_style(row):
    wish = " ".join([row.get("fighting_style_wish (optional)", ""), row.get("personality (3-5 words)", ""),
                     row.get("role", "")]).lower()
    for s in STYLES:
        if s in wish: return s
    for pat, s in STYLE_HINTS:
        if re.search(pat, wish): return s
    return None


def hex_rgb(h):
    h = h.lstrip("#")
    return [round(int(h[i:i + 2], 16) / 255, 3) for i in (0, 2, 4)]


def main():
    rows = list(csv.DictReader(open(os.path.join(ROOT, "design", "CHARACTER_SHEET.csv"))))
    # hand-made design per fighter (style, power, prop, quote, colors, outfit) wins over guesses from the sheet
    design_path = os.path.join(ROOT, "design", "fighters.json")
    designs = json.load(open(design_path)) if os.path.exists(design_path) else {}
    people = []
    rr = 0
    for i, r in enumerate(rows):
        name = r["name"].strip()
        if not name: continue
        boss = (r.get("boss") or "").lower()
        boss = "final" if "final" in boss else "mini" if "mini" in boss else "bonus" if "bonus" in boss else ""
        d = designs.get(name, {})
        style = d.get("style") or pick_style(r)
        if style is None:
            style = STYLES[rr % len(STYLES)]; rr += 1
        body = (r.get("body_model (masculine/feminine)") or "").lower()
        model = "female" if body.startswith("fem") else "male" if body.startswith("mas") else "android"
        if boss == "final" and model == "android": model = "male"   # Hamza: stated "him" in the brief
        accent = color_of(r.get("favorite_color"), hue_color(i, len(rows)))
        try: h = float(r.get("height_cm") or 0)
        except ValueError: h = 0
        scale = round(min(1.12, max(0.78, h / 172.0)), 3) if h else 1.0
        skills = [s.strip() for s in re.split(r"[,/;]", r.get("skills (from work, e.g. Python, React, Design)") or "") if s.strip()]
        role = d.get("role") or (r.get("role") or "").strip() or "Team Member"
        surge = d.get("power") or ((skills[0] + " Overdrive") if skills else "")
        if "accent" in d: accent = hex_rgb(d["accent"])
        beard = (r.get("beard (y/n)") or "").lower()
        extras = ["mustache"] if "mustache" in beard else (["beard"] if beard.startswith("y") else [])
        for x in d.get("extras", []):
            if x not in extras: extras.append(x)
        people.append({
            "id": slug(name), "name": (r.get("in_game_name") or name).strip().upper(), "title": role,
            "origin": "BIT & BYTES  ·  " + role.upper(), "base": style,
            "style": STYLE_NAMES[style] + "  —  " + (d.get("personality") or ", ".join(skills[:3]) or "Bit & Bytes"),
            "quote": d.get("quote") or (r.get("catchphrase (optional)") or "").strip() or "Let's ship it.",
            "prop": d.get("prop", ""), "outfit_kind": d.get("outfit", "casual"), "extras": extras, "skin": d.get("skin", []),
            "idle": d.get("idle", ""), "pose": d.get("pose", ""), "intro": d.get("intro", ""), "win": d.get("win", ""),
            "hair_style": d.get("hair_style", ""), "hair_color": d.get("hair_color", []), "head": d.get("head", [1, 1, 1]),
            "face": d.get("face", {}), "eyes": d.get("eyes", []), "intro_prop": d.get("intro_prop", ""),
            "power_anim": d.get("power_anim", ""), "fx": d.get("fx", []),
            "boss": boss, "model": model, "scale": scale, "accent": accent, "surge": surge,
            "hair": (r.get("hair (color + style)") or "").strip(), "glasses": (r.get("glasses (y/n)") or "").lower().startswith("y"),
            "beard": (r.get("beard (y/n)") or "").lower().startswith("y"), "outfit": (r.get("outfit (formal / smart-casual / hoodie / hijab+abaya / etc.)") or "").strip(),
            "personality": d.get("personality") or (r.get("personality (3-5 words)") or "").strip(), "skills": skills,
        })
        if boss == "final":   # playable Hamza is toned down; his boss form in Arcade is not
            people[-1].update(hp_mult=0.95, power_mult=0.9)
    # short names for the select cards: skip common first names, then make each one unique
    used = set()
    for p in people:
        words = [w for w in p["name"].split() if w.lower() not in ("muhammad", "syeda", "syed", "ud", "abdul")]
        short = words[0] if words else p["name"].split()[0]
        if short in used and len(words) > 1: short = words[-1]
        used.add(short)
        p["short"] = short
    # the bosses close out the select screen
    order = {"": 0, "bonus": 1, "mini": 2, "final": 3}
    people.sort(key=lambda p: order[p["boss"]])
    json.dump({"people": people}, open(os.path.join(ROOT, "data", "bnb_roster.json"), "w"), indent=1)
    print(f"{len(people)} fighters -> data/bnb_roster.json")
    for p in people:
        print(f"  {p['id']:<24} {p['base']:<8} {p['model']:<8} {p['boss'] or '-':<6} {p['title']}")


if __name__ == "__main__":
    main()
