# BNB Clashes

The Bit & Bytes office fighter. Every fighter is someone from the team, the arenas are our office,
and at the top of the ladder waits the CEO.

Built on the Clash Circuit engine (Godot 4.3): 3D fighting with frame data, strings, juggles, throws,
Surge Arts, motion-captured strikes, touch controls, online rooms and same-Wi-Fi play.

## Modes
- **Arcade**: four colleagues, then **Kashaf ud Duja (HR, mini boss)**, **Muhammad Mubarak (PM, bonus boss)**
  and **Hamza Khan (CEO, final boss)**. Bosses fight in a stronger form: more health, harder hits, a boss-level CPU and an aura.
  Hamza is also playable, in a toned-down form.
- **VS CPU / Versus / Online / Training**: as in Clash Circuit.

## Arenas
Open Office · Server Room · Boardroom · Cafeteria · HQ Rooftop

## The roster
All fighters come from `design/CHARACTER_SHEET.csv` (one row per person). Fill in role, body model, height,
personality, skills, look and catchphrase, then run:

```bash
python3 tools/gen_roster.py      # writes data/bnb_roster.json
./run.sh
```

Each person is built on one of 8 base fighting styles (picked from their role / personality / style wish),
with their own name, role, colors, outfit (3 costumes), height, Surge name (from their skills) and quote.
Fighters are original anime-style characters; no photos or likenesses are used.
Until a row says "masculine" or "feminine", that fighter uses a neutral android body.

## Builds
Same as Clash Circuit: `./build_android.sh`, `./build_desktop.sh`, `./build_ios.sh` (+ the iOS GitHub Actions workflow).
Online rooms use the relay in `server/` (rooms are namespaced per game, so one relay can serve both games).

## Credits
Company logo © Bit & Bytes. Engine, models and animation credits: see `CREDITS.md`.
