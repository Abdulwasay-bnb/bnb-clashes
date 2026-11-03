# Making the fighters in VRoid Studio

The game loads any VRM 1.0 file saved as `characters/<id>/model.vrm` automatically.
Fighter ids: `vex`, `bastion`, `sora`, `ember`, `mara`, `lio`, `tao`, `kael`.

## Steps (about 15–30 minutes per fighter)
1. Open VRoid Studio and click **Create New**.
2. Pick the **Masculine** or **Feminine** base, then shape the body under **Body**.
3. Style the face, hair and outfit with the briefs below.
4. Click **Export** (the share icon at the top right) → **Export as VRM** → choose **VRM 1.0**.
5. When asked for the avatar info, fill in a title and author. Set **"Violent acts using the avatar" = Allow**.
6. Save it to the fighter's folder, for example:
   `~/Documents/bnb-clashes-godot/characters/kael/model.vrm`
7. Launch the game. That fighter now uses your model. No code changes are needed.

Tip: keep the polygon reduction in the export dialog at its default. Two fighters on an Intel Iris
Xe run fine with standard VRoid exports.

## Priority: the four men (no model yet)

### Bastion: Harbor Heavyweight (`bastion`)
- **Body:** Masculine. Height and shoulder width near max, thick arms and neck, broad chest.
- **Face:** square jaw, heavy brows, narrow, tired eyes. Short beard (Hair → Beard, or a dark
  lower-face texture).
- **Hair:** shaved / very short, dark.
- **Outfit:** red tank top, dark grey work pants, brown boots, black fingerless gloves, orange belt.
- **Colors:** skin warm brown `#7a4e36`, accent orange `#ff6a2b`.

### Lio Ferraz: Roda Rebel, capoeira (`lio`)
- **Body:** Masculine. Average height, lean and long-limbed.
- **Face:** friendly, confident smile, bright green eyes.
- **Hair:** shoulder-length locs, dark brown, tied back loosely.
- **Outfit:** shirtless (or an open vest), loose white capoeira pants with a green cord belt
  (`#3ddc84`), barefoot.
- **Colors:** skin `#b07850`.

### Tao Ren: The Last Iron Monk (`tao`)
- **Body:** Masculine. Average height, slim but upright, older posture.
- **Face:** calm, narrowed eyes, long grey eyebrows. Long grey mustache and beard.
- **Hair:** grey/silver, pulled into a top-knot.
- **Outfit:** deep red high-collar kung-fu jacket with gold frog buttons and trim (`#d4a640`),
  black trousers, black cloth shoes, gold sash.

### Kael Varga: The Eight-Limbed Storm, Muay Thai (`kael`)
- **Body:** Masculine. Tall, athletic, defined arms and legs.
- **Face:** sharp eyes, short scar on one eyebrow, serious expression.
- **Hair:** short buzz cut, dark.
- **Outfit:** shirtless, royal-blue Thai shorts with a gold waistband, white hand wraps, red and
  white headband, red armbands, ankle wraps, barefoot.
- **Colors:** skin `#c49a6c`, accent red `#e63946`.

## Optional: unique models for the women (they currently share one base)

### Sora Hayame (`sora`)
Feminine, slim. Long black ponytail, mint-green headband (`#7cf29a`). White taekwondo top with a
black V-collar and black belt, navy pants, barefoot.

### Ember Cruz (`ember`)
Feminine, athletic. Purple wrestling mask with gold eye trim (a hat or face texture), red ponytail
out the back. Purple sleeveless leotard, purple tights with orange flame stripes, gold boots,
orange MMA gloves.

### Mara Okonkwo (`mara`)
Feminine, athletic. Deep brown skin, black braids. Red sports top and red boxing trunks with a gold
waistband, red boxing gloves, white high-top boxing boots.

### VEX-9 (`vex`)
Currently uses the Seed-san sample. For a custom look: androgynous, white and gunmetal armor
plates, cyan visor across the eyes, glowing cyan chest core.
