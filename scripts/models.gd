class_name Models
## Which VRM model each fighter uses, and their costumes.
## A fighter's own model at characters/<id>/model.vrm always replaces the base model (see VROID_GUIDE.md);
## costume accessories still apply on top of it.
##
## Bases (credits in CREDITS.md):
##   seed_san.vrm      "Seed-san" by VirtualCast, Inc. (VRM Public License 1.0, credit required)
##   twist_sample.vrm  VRM1_Constraint_Twist_Sample by pixiv Inc. (VRM Public License 1.0)
##   base_male.vrm     VRoid "Base_Male" by the VRoid Project (CC0)
##
## Costume = {name, tint, acc}
##   tint: material-name substring -> Color multiplier, {c, sat, bright} recolor (sat 0 = grey), or "hide"
##   acc:  accessories attached to bones: [kind, Color] with kind in
##         gloves, wraps, headband, belt, sash, armbands, visor, kneepads, shoulders

const SEED := "res://characters/_base/seed_san.vrm"
const GIRL := "res://characters/_base/twist_sample.vrm"
const MALE := "res://characters/_base/base_male.vrm"


static func spec(id: String, costume := 0) -> Dictionary:
	if not LIST.has(id):
		return {}
	var e: Dictionary = LIST[id]
	var cs: Dictionary = e.costumes[clampi(costume, 0, e.costumes.size() - 1)]
	var own := "res://characters/%s/model.vrm" % id
	if FileAccess.file_exists(own):
		return {file = own, tint = {}, acc = cs.get("acc", [])}
	return {file = e.file, tint = _with_prints(cs.get("tint", {}), PRINTS.get(id, [])[costume] if costume < PRINTS.get(id, []).size() else {}), acc = cs.get("acc", [])}


## Merge a costume's prints into its tints (a plain Color tint becomes {c = Color} so it can carry a pattern).
static func _with_prints(tint: Dictionary, prints: Dictionary) -> Dictionary:
	var out := tint.duplicate()
	for part in prints:
		var t = out.get(part, {})
		var d: Dictionary = (t as Dictionary).duplicate() if t is Dictionary else {c = t if t is Color else Color.WHITE}
		d.pat = prints[part]
		out[part] = d
	return out


static func costume_names(id: String) -> Array:
	return LIST[id].costumes.map(func(c): return c.name) if LIST.has(id) else ["Classic"]


static func skin(c: Color) -> Dictionary:
	return {"Body_00_SKIN": c, "Face_00_SKIN": c}


## Costume prints per fighter, in costume order: material-name substring -> pattern (see VrmRig._set_pattern).
const PRINTS := {
	"vex": [
		{"huku": {kind = "grid", a = Color(0.2, 0.75, 0.95), b = Color(0.5, 1.0, 1.0), scale = 1.2}},
		{"huku": {kind = "grid", a = Color(0.55, 0.12, 0.15), b = Color(1.0, 0.35, 0.3), scale = 1.2}},
		{"huku": {kind = "camo", a = Color(0.2, 0.21, 0.24), b = Color(0.45, 0.47, 0.5), scale = 1.0}},
	],
	"sora": [
		{"Bottoms": {kind = "gradient", a = Color(0.08, 0.08, 0.12), o = 0.25}},
		{"Tops": {kind = "camo", a = Color(0.32, 0.34, 0.38), b = Color(0.8, 0.82, 0.86), scale = 1.0}},
		{"Tops": {kind = "diagonal", a = Color(0.82, 0.76, 0.74), b = Color(0.9, 0.7, 0.2), scale = 1.0}},
	],
	"ember": [
		{"Bottoms": {kind = "flames", a = Color(1.0, 0.45, 0.1), b = Color(1.0, 0.85, 0.3), o = 0.12},
			"Tops": {kind = "diagonal", a = Color(1.0, 0.75, 0.2), b = Color(0.35, 0.1, 0.55), scale = 0.8}},
		{"Tops": {kind = "scales", a = Color(0.35, 0.05, 0.02), b = Color(1.0, 0.45, 0.15), scale = 1.0},
			"Bottoms": {kind = "flames", a = Color(1.0, 0.35, 0.1), b = Color(1.0, 0.8, 0.25), o = 0.12}},
		{"Tops": {kind = "dots", a = Color(1.0, 0.82, 0.35), scale = 1.0}},
	],
	"mara": [
		{"Bottoms": {kind = "bands", a = Color(1.0, 1.0, 1.0), b = Color(1.0, 0.8, 0.25), o = 0.0, scale = 1.0}},
		{"Tops": {kind = "pinstripes", a = Color(1.0, 0.8, 0.3), scale = 1.0}},
		{"Tops": {kind = "camo", a = Color(0.5, 0.52, 0.56), b = Color(0.9, 0.9, 0.92), scale = 1.0}},
	],
	"bastion": [
		{"Tops": {kind = "plaid", a = Color(0.12, 0.05, 0.05), b = Color(0.95, 0.75, 0.3), scale = 1.0}},
		{"Tops": {kind = "bands", a = Color(0.85, 0.88, 0.9), b = Color(0.2, 0.2, 0.2), o = 0.05, scale = 0.6}},
		{"Bottoms": {kind = "camo", a = Color(0.26, 0.28, 0.33), b = Color(0.42, 0.45, 0.52), scale = 1.0}},
	],
	"lio": [
		{"Tops": {kind = "gradient", a = Color(1.0, 0.85, 0.2), o = 0.75}},
		{"Tops": {kind = "diagonal", a = Color(0.25, 0.45, 1.0), b = Color(1.0, 1.0, 1.0), scale = 0.8},
			"Bottoms": {kind = "dots", a = Color(1.0, 0.85, 0.2), scale = 1.0}},
		{},
	],
	"tao": [
		{"Tops": {kind = "scales", a = Color(0.95, 0.72, 0.25), b = Color(0.6, 0.08, 0.06), scale = 1.0}},
		{"Tops": {kind = "scales", a = Color(0.08, 0.3, 0.2), b = Color(0.25, 0.75, 0.5), scale = 1.0}},
		{"Tops": {kind = "gradient", a = Color(0.85, 0.85, 0.85), o = 0.68}},
	],
	"kael": [
		{"Bottoms": {kind = "pinstripes", a = Color(1.0, 1.0, 1.0), scale = 0.6}},
		{"Bottoms": {kind = "scales", a = Color(0.65, 0.42, 0.08), b = Color(1.0, 0.85, 0.35), scale = 1.0}},
		{"Tops": {kind = "camo", a = Color(0.95, 0.5, 0.08), b = Color(0.7, 0.32, 0.05), scale = 1.4}},
	],
}


## BNB Clashes: build a fighter's model + 3 costumes from their roster entry (see tools/gen_roster.py).
## model: "male" / "female" use the VRoid bases, "android" is the neutral placeholder until the sheet says otherwise.
static func register(p: Dictionary) -> void:
	var a: Array = p.accent
	var acc := Color(a[0], a[1], a[2])
	var BV := Color(0.55, 0.32, 0.92)   # BNB violet
	var GD := Color(0.13, 0.78, 0.92)   # Bit & Bytes cyan
	var costumes: Array = []
	match String(p.model):
		"android":
			costumes = [
				{name = "Office", tint = {"huku": {c = acc, sat = 0.0, bright = 0.8, pat = {kind = "grid", a = acc.darkened(0.35), b = acc.lightened(0.4), scale = 1.2}}},
					acc = [["visor", acc]]},
				{name = "Hoodie", tint = {"huku": {c = Color(0.4, 0.42, 0.46), sat = 0.0, bright = 0.6, pat = {kind = "camo", a = Color(0.3, 0.31, 0.35), b = acc.darkened(0.2), scale = 1.0}}},
					acc = [["visor", acc], ["kneepads", Color(0.12, 0.12, 0.14)]]},
				{name = "Launch Day", tint = {"huku": {c = BV, sat = 0.0, bright = 0.7, pat = {kind = "diagonal", a = BV.darkened(0.3), b = GD, scale = 0.8}}},
					acc = [["visor", GD], ["shoulders", BV.darkened(0.5)]]},
			]
		_:
			var female := String(p.model) == "female"
			var hair := _hair(String(p.get("hair", "")), female)
			var skin_c := Color(0.86, 0.7, 0.58) if female else Color(0.8, 0.62, 0.48)
			var sk: Array = p.get("skin", [])
			if sk.size() == 3: skin_c = Color(sk[0], sk[1], sk[2])
			var extra: Array = []
			if p.get("glasses", false): extra.append(["glasses", Color(0.1, 0.1, 0.12)])
			for x in p.get("extras", []):
				extra.append([x, Color(0.3, 0.2, 0.13)])   # dark brown facial hair (pure black reads as tape)
			var kind := String(p.get("outfit_kind", "casual"))
			# [main color, second color, trim]: their own colors, then Casual Friday, then Team BNB
			var palettes := [[acc, acc.darkened(0.55), acc.lightened(0.35)],
				[Color(0.92, 0.9, 0.86), Color(0.24, 0.32, 0.5), acc],
				[BV, Color(0.1, 0.08, 0.16), GD]]
			var names := ["Signature", "Casual Friday", "Team BNB", "Fight Night", "Hacker Hoodie", "Eid Special"]
			if kind == "ceo": names[0] = "Chief Executive"
			# their own haircut replaces the shared base hair (not under a hijab)
			var style := String(p.get("hair_style", ""))
			var hc: Array = p.get("hair_color", [])
			var hair_col := Color(hc[0], hc[1], hc[2]) if hc.size() == 3 else Color(0.09, 0.07, 0.06)
			var ey: Array = p.get("eyes", [])
			for k in 6:
				var o := _outfit(kind, palettes[k], hair, female, k) if k < 3 else _extra_outfit(k, kind, acc, hair, female)
				if k == 0 and kind in ["formal", "smart", "staff", "ceo", "formal_f", "casual"]:
					o.acc.append(["lanyard", Color(0.55, 0.32, 0.92)])   # their BNB ID badge
				var tint: Dictionary = o.tint
				tint.merge(skin(skin_c))
				var parts: Array = o.acc + extra
				if style != "" and kind != "hijab":
					# men keep the full base hair (recoloured) and get their cut on top, so nobody looks bald;
					# women's cuts and Mubarak's swept-back look replace it
					if female or style == "hair_back_full":
						tint["Hair"] = "hide"
					else:
						tint["Hair"] = {c = hair_col * 3.0, sat = 0.0, bright = 0.55}
					parts.append([style, hair_col])
				if ey.size() == 3:
					tint["EyeIris"] = {c = Color(ey[0], ey[1], ey[2]) * 2.2, sat = 1.0, bright = 1.0}
				costumes.append({name = names[k], tint = tint, acc = parts})
			# their own one-of-a-kind look goes first (the default costume)
			if PERSONA.has(String(p.id)):
				var po := _persona_outfit(String(p.id), hair, female, kind)
				var ptint: Dictionary = po.tint
				var goat := String(p.id) == "tuaha_aamir"
				if goat:
					# fur instead of skin: cream with tan patches and strand shading; no human hair, glasses or beard
					var fur := {c = Color(0.78, 0.6, 0.42), sat = 0.0, bright = 0.8, sheen = 1.0, pat = {kind = "camo", a = Color(0.62, 0.45, 0.3), b = Color(0.92, 0.86, 0.74), scale = 1.4}}
					ptint.merge({"Body_00_SKIN": fur, "Face_00_SKIN": fur, "Hair": "hide"}, true)
				else:
					ptint.merge(skin(skin_c))
				var pparts: Array = po.acc + ([] if goat else extra)
				if style != "" and kind != "hijab" and not goat:
					if female or style == "hair_back_full": ptint["Hair"] = "hide"
					else: ptint["Hair"] = {c = hair_col * 3.0, sat = 0.0, bright = 0.55}
					pparts.append([style, hair_col])
				if ey.size() == 3:
					ptint["EyeIris"] = {c = Color(ey[0], ey[1], ey[2]) * 2.2, sat = 1.0, bright = 1.0}
				costumes.push_front({name = po.name, tint = ptint, acc = pparts})
			# full-body mascot suits go first of all for the people who have one
			if MASCOT.has(String(p.id)):
				var mo := _mascot_outfit(String(p.id), female)
				var mtint: Dictionary = mo.tint
				mtint.merge(skin(skin_c))
				if ey.size() == 3:
					mtint["EyeIris"] = {c = Color(ey[0], ey[1], ey[2]) * 2.2, sat = 1.0, bright = 1.0}
				costumes.push_front({name = mo.name, tint = mtint, acc = mo.acc})
	LIST[p.id] = {file = {"android": SEED, "female": GIRL}.get(String(p.model), MALE), costumes = costumes}


## One outfit as material tints + garment accessories. kind comes from design/fighters.json.
static func _outfit(kind: String, pal: Array, hair: Dictionary, female: bool, variant: int) -> Dictionary:
	var main: Color = pal[0]
	var second: Color = pal[1]
	var trim: Color = pal[2]
	var T := func(c: Color, bright := 0.75) -> Dictionary: return {c = c, sat = 0.0, bright = bright}
	# men's shirt texture has a dark vest painted in: repaint it solid when the outfit needs a plain top
	var S := func(c: Color, bright := 0.75) -> Dictionary: return {c = Color.WHITE, sat = 0.0, bright = bright, pat = {kind = "solid", a = c}}
	var dark := Color(0.12, 0.11, 0.14)
	var tint := {"Hair": hair, "Tie": "hide"}
	var acc: Array = []
	match kind:
		"all_black":
			tint.merge({"Tops": T.call(dark if variant == 0 else main, 0.45), "Bottoms": T.call(dark, 0.4), "Shoes": T.call(Color(0.1, 0.1, 0.1), 0.35)}, true)
			acc.append(["shoulders", dark.lightened(0.08)])
		"formal":
			tint.merge({"Tops": T.call(Color(0.95, 0.95, 0.97) if variant == 0 else main, 0.72), "Bottoms": T.call(dark if variant != 1 else second, 0.42),
				"Shoes": T.call(Color(0.1, 0.09, 0.08), 0.35), "Tie": T.call(trim if variant != 0 else main, 0.85)}, true)
		"smart":
			tint.merge({"Tops": S.call(Color(0.62, 0.75, 0.92) if variant == 0 else main, 0.72), "Bottoms": T.call(Color(0.72, 0.62, 0.45) if variant == 0 else second, 0.6),
				"Shoes": T.call(Color(0.3, 0.2, 0.12), 0.45)}, true)
		"ceo":
			tint.merge({"Tops": {c = Color(0.12, 0.1, 0.18) if variant == 0 else main, sat = 0.0, bright = 0.4, pat = {kind = "pinstripes", a = Color(0.3, 0.26, 0.38), scale = 0.5}},
				"Bottoms": T.call(Color(0.1, 0.09, 0.14), 0.35), "Shoes": T.call(Color(0.08, 0.07, 0.07), 0.3), "Tie": T.call(Color(0.58, 0.3, 0.85) if variant == 0 else trim, 0.9)}, true)
		"staff":   # office staff: plain polo shirt, work trousers
			tint.merge({"Tops": S.call(Color(0.32, 0.45, 0.62) if variant == 0 else main, 0.75), "Bottoms": T.call(Color(0.2, 0.2, 0.24) if variant != 1 else second, 0.5),
				"Shoes": T.call(Color(0.12, 0.1, 0.09), 0.4)}, true)
		"kurta":
			tint.merge({"Tops": S.call(Color(0.86, 0.82, 0.72) if variant == 0 else main, 0.75), "Bottoms": T.call(Color(0.9, 0.86, 0.76) if variant == 0 else second, 0.7),
				"Shoes": T.call(Color(0.35, 0.22, 0.12), 0.45)}, true)
			acc.append(["kameez", Color(0.9, 0.86, 0.76) if variant == 0 else main])
		"pakistani":
			tint.merge({"Tops": T.call(main), "Bottoms": T.call(trim), "Shoes": T.call(Color(0.85, 0.7, 0.4), 0.7)}, true)
			acc.append_array([["kameez", main], ["shalwar", trim], ["sleeves", main], ["dupatta", second.lightened(0.25) if variant == 0 else trim]])
		"hijab":
			tint.merge({"Hair": "hide", "Tops": T.call(second.lightened(0.15)), "Bottoms": T.call(second), "Shoes": T.call(Color(0.15, 0.14, 0.16), 0.4)}, true)
			acc.append_array([["hijab", main], ["kameez", second.lightened(0.15)], ["shalwar", second], ["sleeves", second.lightened(0.15)]])
		"formal_f":
			tint.merge({"Tops": T.call(Color(0.2, 0.18, 0.26) if variant == 0 else second, 0.5), "Bottoms": T.call(Color(0.2, 0.18, 0.26), 0.45),
				"Shoes": T.call(Color(0.1, 0.09, 0.1), 0.35)}, true)
			acc.append_array([["sleeves", Color(0.2, 0.18, 0.26) if variant == 0 else second], ["shalwar", Color(0.2, 0.18, 0.26)], ["kameez", main if variant == 0 else trim]])
		_:   # casual
			tint.merge({"Tops": S.call(main) if not female else T.call(main), "Bottoms": T.call(Color(0.22, 0.3, 0.48) if variant == 0 else second, 0.6),
				"Shoes": T.call(Color(0.9, 0.9, 0.92), 0.85)}, true)
	# men's base model wears trousers already; the women's base wears shorts, so cover the legs for every women's outfit
	if female and not kind in ["pakistani", "hijab", "formal_f"]:
		acc.append(["shalwar", second])
	return {tint = tint, acc = acc}


## The extra costumes everyone gets: 3 Fight Night, 4 Hacker Hoodie, 5 Eid Special.

## Everyone's own signature look (their default costume): [name, top, bottoms, shoes, parts].
## top: [color, pattern, pattern a, pattern b, scale] (pattern "" = plain); parts: [gear, color].
const GOLD := Color(1.0, 0.8, 0.3)
const PERSONA := {
	"abdul_wasay": ["Agent Ops", [Color(0.08, 0.08, 0.1), "grid", Color(0.13, 0.78, 0.92), Color(0.6, 0.95, 1.0), 1.2], Color(0.06, 0.06, 0.08), Color(0.08, 0.08, 0.1),
		[["backpack", Color(0.12, 0.12, 0.15)], ["armbands", Color(0.13, 0.78, 0.92)], ["visor", Color(0.13, 0.78, 0.92)]]],
	"abdul_wasay_waqas": ["Pythonista", [Color(0.2, 0.38, 0.68), "diagonal", Color(0.24, 0.45, 0.78), Color(1.0, 0.84, 0.25), 0.8], Color(0.16, 0.2, 0.3), Color(0.95, 0.95, 0.95),
		[["beanie", Color(1.0, 0.84, 0.25)], ["hood", Color(0.2, 0.38, 0.68)]]],
	"amina_mughal": ["Stand-up Queen", [Color(1.0, 0.86, 0.4), "dots", Color(1.0, 0.45, 0.65), Color(0, 0, 0, 0), 1.0], Color(0.95, 0.92, 0.88), Color(0.85, 0.4, 0.55),
		[["kameez", Color(1.0, 0.72, 0.8)], ["shalwar", Color(0.95, 0.92, 0.88)], ["sleeves", Color(1.0, 0.72, 0.8)], ["dupatta", Color(1.0, 0.86, 0.4)], ["lanyard", Color(0.55, 0.32, 0.92)]]],
	"aqsa_altaf": ["Ruby Red", [Color(0.7, 0.06, 0.16), "scales", Color(0.9, 0.18, 0.3), Color(0.5, 0.02, 0.1), 1.0], Color(0.35, 0.04, 0.08), Color(0.2, 0.05, 0.07),
		[["hijab", Color(0.75, 0.08, 0.2)], ["kameez", Color(0.7, 0.08, 0.18)], ["shalwar", Color(0.3, 0.05, 0.08)], ["sleeves", Color(0.7, 0.08, 0.18)], ["chain", GOLD]]],
	"daniyal_zubair": ["Paint Splash", [Color(0.95, 0.95, 0.95), "camo", Color(1.0, 0.45, 0.15), Color(0.2, 0.75, 0.95), 1.4], Color(0.25, 0.3, 0.45), Color(0.95, 0.4, 0.2),
		[["apron", Color(0.85, 0.8, 0.7)], ["beret", Color(0.85, 0.15, 0.2)], ["palette", Color(0.82, 0.62, 0.38)],
			["dab0", Color(0.95, 0.2, 0.2)], ["dab1", Color(1.0, 0.85, 0.1)], ["dab2", Color(0.2, 0.6, 1.0)],
			["dab3", Color(0.25, 0.8, 0.3)], ["dab4", Color(0.95, 0.95, 0.95)], ["dab5", Color(0.7, 0.3, 0.9)], ["paint_brush", Color(0.55, 0.35, 0.18)]]],
	"faizan_ali": ["Chill Mode", [Color(0.78, 0.8, 0.84), "gradient", Color(0.5, 0.75, 0.95), Color(0, 0, 0, 0), 1.0], Color(0.4, 0.42, 0.46), Color(0.95, 0.95, 0.95),
		[["shades", Color(0.08, 0.08, 0.1)], ["hood", Color(0.7, 0.72, 0.76)], ["scarf", Color(0.5, 0.75, 0.95)]]],
	"faisal_ahmed": ["Root Admin", [Color(0.06, 0.08, 0.06), "grid", Color(0.15, 0.85, 0.35), Color(0.6, 1.0, 0.7), 1.4], Color(0.06, 0.07, 0.06), Color(0.05, 0.05, 0.05),
		[["coat", Color(0.08, 0.1, 0.08)], ["shades", Color(0.05, 0.05, 0.05)]]],
	"kiran_fazal": ["Deal Closer", [Color(0.12, 0.08, 0.16), "pinstripes", Color(0.75, 0.25, 0.82), Color(0, 0, 0, 0), 0.6], Color(0.12, 0.08, 0.16), Color(0.08, 0.06, 0.08),
		[["kameez", Color(0.14, 0.09, 0.18)], ["shalwar", Color(0.12, 0.08, 0.16)], ["sleeves", Color(0.14, 0.09, 0.18)], ["chain", GOLD], ["shades", Color(0.08, 0.06, 0.08)]]],
	"mahveen_khan": ["Call Centre", [Color(1.0, 0.62, 0.2), "dots", Color(1.0, 0.85, 0.5), Color(0, 0, 0, 0), 1.0], Color(0.95, 0.9, 0.82), Color(0.5, 0.3, 0.15),
		[["kameez", Color(1.0, 0.62, 0.22)], ["shalwar", Color(0.95, 0.9, 0.82)], ["sleeves", Color(1.0, 0.62, 0.22)], ["dupatta", Color(1.0, 0.85, 0.5)], ["headphones", Color(0.1, 0.1, 0.12)]]],
	"muhammad_saad": ["Push Notify", [Color(0.14, 0.15, 0.2), "dots", Color(0.95, 0.25, 0.3), Color(0, 0, 0, 0), 0.7], Color(0.2, 0.22, 0.3), Color(0.95, 0.3, 0.35),
		[["cap_back", Color(0.95, 0.25, 0.3)], ["backpack", Color(0.18, 0.2, 0.28)]]],
	"muhammad_sufyan": ["Premium Plan", [Color(0.08, 0.1, 0.22), "pinstripes", GOLD, Color(0, 0, 0, 0), 0.5], Color(0.08, 0.1, 0.2), Color(0.3, 0.18, 0.08),
		[["bowtie", GOLD], ["chain", GOLD], ["watch", GOLD], ["shades", Color(0.06, 0.06, 0.08)]]],
	"muzdalfa_naeem": ["Inbox Zero", [Color(0.62, 0.42, 1.0), "diagonal", Color(0.75, 0.6, 1.0), Color(1.0, 1.0, 1.0), 0.9], Color(0.25, 0.18, 0.4), Color(0.2, 0.15, 0.3),
		[["kameez", Color(0.62, 0.45, 1.0)], ["shalwar", Color(0.25, 0.18, 0.4)], ["sleeves", Color(0.62, 0.45, 1.0)], ["scarf", Color(1.0, 1.0, 1.0)], ["lanyard", Color(0.55, 0.32, 0.92)]]],
	"nabeel_ahmad": ["Snack Commander", [Color(0.95, 0.75, 0.25), "dots", Color(0.6, 0.35, 0.15), Color(0, 0, 0, 0), 0.8], Color(0.3, 0.25, 0.2), Color(0.5, 0.3, 0.15),
		[["apron", Color(0.9, 0.3, 0.25)], ["cap_back", Color(0.9, 0.3, 0.25)], ["armbands", Color(0.95, 0.75, 0.25)]]],
	"muhammad_nauman_nawaz": ["Banana Republic", [Color(1.0, 0.88, 0.2), "dots", Color(0.45, 0.3, 0.1), Color(0, 0, 0, 0), 1.3], Color(0.35, 0.5, 0.25), Color(0.95, 0.85, 0.3),
		[["bandana", Color(1.0, 0.88, 0.2)], ["shades", Color(0.08, 0.08, 0.08)]]],
	"sabir_ud_din": ["Howzat XI", [Color(0.97, 0.97, 0.95), "bands", Color(0.1, 0.55, 0.3), Color(1.0, 0.8, 0.3), 1.0], Color(0.97, 0.97, 0.95), Color(0.95, 0.95, 0.95),
		[["pads", Color(0.97, 0.97, 0.95)], ["cricket_helmet", Color(0.1, 0.4, 0.22)], ["helmet_grille", Color(0.75, 0.75, 0.78)],
			["batting_gloves", Color(0.97, 0.97, 0.95)], ["thigh_pad", Color(0.97, 0.97, 0.95)], ["cricket_bat", Color(0.92, 0.8, 0.55)]]],
	"samreen_fatima": ["Pixel Art", [Color(0.0, 0.6, 0.55), "grid", Color(1.0, 0.3, 0.75), Color(1.0, 0.95, 0.4), 1.6], Color(0.12, 0.2, 0.3), Color(0.95, 0.95, 0.95),
		[["hijab", Color(0.0, 0.7, 0.62)], ["kameez", Color(0.05, 0.55, 0.5)], ["shalwar", Color(0.12, 0.2, 0.3)], ["sleeves", Color(0.05, 0.55, 0.5)], ["backpack", Color(1.0, 0.3, 0.75)]]],
	"sarfraz_yousaf": ["Stand-up Comic", [Color(0.95, 0.75, 0.2), "plaid", Color(0.85, 0.2, 0.2), Color(0.1, 0.1, 0.1), 1.2], Color(0.15, 0.15, 0.2), Color(0.85, 0.2, 0.2),
		[["bowtie", Color(0.9, 0.15, 0.2)], ["shades", Color(0.9, 0.15, 0.2)]]],
	"syeda_ghazia": ["Hello World", [Color(0.42, 0.6, 0.85), "bands", Color(0.95, 0.97, 1.0), Color(0.3, 0.9, 0.5), 1.0], Color(0.2, 0.25, 0.4), Color(0.95, 0.95, 0.95),
		[["hijab", Color(0.72, 0.6, 0.95)], ["kameez", Color(0.42, 0.6, 0.85)], ["shalwar", Color(0.2, 0.25, 0.4)], ["sleeves", Color(0.42, 0.6, 0.85)], ["lanyard", Color(0.55, 0.32, 0.92)]]],
	# the G.O.A.T. himself: an anime goat-man in his gold-striped jersey (fur, horns, beard, goat eyes; hooves for shoes)
	"tuaha_aamir": ["G.O.A.T. Form", [Color(0.95, 0.95, 0.95), "bands", GOLD, Color(0.1, 0.1, 0.1), 1.2], Color(0.14, 0.12, 0.12), Color(0.18, 0.15, 0.13),
		[["goat_head", Color(0.84, 0.7, 0.52)], ["goat_horns", Color(0.62, 0.52, 0.38)], ["goat_nose", Color(0.22, 0.17, 0.17)],
			["goat_eyes", Color(1.0, 0.72, 0.18)], ["goat_pupils", Color(0.05, 0.04, 0.04)], ["fur_arms", Color(0.8, 0.64, 0.46)], ["armbands", GOLD], ["chain", GOLD]]],
	"umar_farooq": ["Overtime", [Color(0.92, 0.92, 0.88), "flames", Color(1.0, 0.48, 0.24), Color(1.0, 0.85, 0.3), 1.0], Color(0.2, 0.2, 0.25), Color(0.25, 0.18, 0.12),
		[["watch", Color(1.0, 0.48, 0.24)], ["headband", Color(1.0, 0.48, 0.24)]]],
	"usman_najeeb": ["Smoke Break", [Color(0.1, 0.1, 0.11), "", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.08, 0.08, 0.1), Color(0.06, 0.06, 0.06),
		[["shades", Color(0.05, 0.05, 0.05)], ["chain", Color(0.75, 0.75, 0.8)], ["bandana", Color(0.45, 0.45, 0.5)], ["shoulders", Color(0.12, 0.12, 0.13)]]],
	"zia_khan": ["Legacy Wizard", [Color(0.12, 0.1, 0.2), "scales", GOLD, Color(0.2, 0.15, 0.3), 1.4], Color(0.1, 0.08, 0.16), Color(0.15, 0.1, 0.08),
		[["coat", Color(0.14, 0.11, 0.24)], ["scarf", GOLD]]],
	"ali": ["Chai Wala", [Color(0.95, 0.9, 0.8), "", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.95, 0.9, 0.8), Color(0.45, 0.28, 0.14),
		[["kameez", Color(0.95, 0.9, 0.8)], ["shalwar", Color(0.95, 0.9, 0.8)], ["sleeves", Color(0.95, 0.9, 0.8)], ["waistcoat", Color(0.42, 0.25, 0.12)],
			["gamcha", Color(0.85, 0.18, 0.15)], ["gamcha_check", Color(0.95, 0.92, 0.85)]]],
	"muhammad_mubarak": ["Viper", [Color(0.15, 0.45, 0.2), "scales", Color(0.3, 0.75, 0.35), Color(0.05, 0.2, 0.08), 1.6], Color(0.08, 0.12, 0.08), Color(0.06, 0.08, 0.06),
		[["shades", Color(0.05, 0.08, 0.05)], ["chain", GOLD]]],
	"kashaf_ud_duja": ["Red Alert", [Color(0.75, 0.1, 0.16), "pinstripes", Color(0.95, 0.4, 0.45), Color(0, 0, 0, 0), 0.6], Color(0.18, 0.08, 0.1), Color(0.1, 0.05, 0.06),
		[["kameez", Color(0.72, 0.1, 0.16)], ["shalwar", Color(0.18, 0.08, 0.1)], ["sleeves", Color(0.72, 0.1, 0.16)], ["scarf", Color(0.95, 0.3, 0.35)], ["lanyard", Color(0.95, 0.2, 0.3)]]],
	"hamza_khan": ["Boardroom Boss", [Color(0.06, 0.05, 0.08), "pinstripes", GOLD, Color(0, 0, 0, 0), 0.5], Color(0.06, 0.05, 0.08), Color(0.05, 0.04, 0.04),
		[["cape", Color(0.45, 0.2, 0.75)], ["shades", Color(0.05, 0.05, 0.05)], ["chain", GOLD], ["watch", GOLD]]],
}


## Full-body mascot suits (kigurumi: the face shows through the hood): [name, suit, pattern [kind, a, b, scale], paws, parts].
const MASCOT := {
	"muhammad_nauman_nawaz": ["Banana Suit", Color(1.0, 0.86, 0.18), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.3, 0.2, 0.08),
		[["banana_tip", Color(1.0, 0.86, 0.18)], ["banana_body", Color(1.0, 0.86, 0.18)], ["banana_ridges", Color(0.85, 0.65, 0.1)],
			["banana_end", Color(0.32, 0.22, 0.08)]], {skip = ["suit_body"], legs = Color(0.3, 0.22, 0.1)}],
	"muhammad_saad": ["Mobile Phone", Color(0.1, 0.1, 0.12), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.1, 0.1, 0.12),
		[["phone_body", Color(0.12, 0.12, 0.14)], ["phone_screen", Color(0.2, 0.45, 0.95)], ["app0", Color(0.95, 0.3, 0.35)], ["app1", Color(0.3, 0.85, 0.4)],
			["app2", Color(1.0, 0.8, 0.2)], ["app3", Color(0.95, 0.95, 0.98)], ["phone_cam", Color(0.03, 0.03, 0.04)], ["phone_back", Color(0.55, 0.56, 0.6)]], {skip = ["suit_body"], legs = Color(0.18, 0.2, 0.28)}],
	"usman_najeeb": ["Cigarette", Color(0.95, 0.95, 0.93), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.08, 0.08, 0.08),
		[["cig_body", Color(0.97, 0.97, 0.95)], ["cig_filter", Color(0.9, 0.55, 0.2)], ["cig_band", GOLD], ["cig_ash", Color(0.45, 0.45, 0.47)],
			["cig_ember", Color(1.0, 0.35, 0.08)], ["cig_smoke", Color(0.75, 0.76, 0.8)]], {skip = ["suit_body"], legs = Color(0.08, 0.08, 0.09)}],
	"nabeel_ahmad": ["Big Burger", Color(0.5, 0.27, 0.12), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.85, 0.55, 0.25),
		[["bun_top", Color(0.88, 0.55, 0.22)], ["sesame", Color(1.0, 0.95, 0.8)], ["lettuce", Color(0.35, 0.75, 0.2)], ["cheese", Color(1.0, 0.75, 0.1)],
			["patty", Color(0.35, 0.18, 0.08)], ["bun_bottom", Color(0.85, 0.52, 0.2)]]],
	"muhammad_mubarak": ["King Cobra", Color(0.18, 0.5, 0.2), ["scales", Color(0.35, 0.75, 0.3), Color(0.08, 0.25, 0.08), 2.0], Color(0.9, 0.85, 0.45),
		[["snake_hood", Color(0.2, 0.55, 0.22)], ["snake_eyes", Color(1.0, 0.85, 0.1)], ["snake_fangs", Color(1.0, 1.0, 0.95)], ["snake_tail", Color(0.2, 0.5, 0.2)]]],
	"faizan_ali": ["Smoke Form", Color(0.55, 0.57, 0.62), ["gradient", Color(0.8, 0.82, 0.86), Color(0, 0, 0, 0), 1.0], Color(0.7, 0.72, 0.76),
		[["smoke_head", Color(0.72, 0.74, 0.78)], ["smoke_body", Color(0.66, 0.68, 0.72)]]],
	"hamza_khan": ["Lion King", Color(0.85, 0.62, 0.3), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.95, 0.85, 0.65),
		[["lion_mane", Color(0.62, 0.32, 0.1)], ["ears_round", Color(0.85, 0.62, 0.3)], ["tail", Color(0.85, 0.62, 0.3)], ["tail_tuft", Color(0.55, 0.28, 0.08)]]],
	"abdul_wasay": ["Raging Bull", Color(0.45, 0.25, 0.14), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.15, 0.1, 0.08),
		[["bull_horns", Color(0.95, 0.9, 0.78)], ["bull_snout", Color(0.75, 0.55, 0.48)], ["nose_ring", GOLD], ["ears_side", Color(0.45, 0.25, 0.14)],
			["tail", Color(0.45, 0.25, 0.14)], ["tail_tuft", Color(0.1, 0.07, 0.05)]]],
	"sarfraz_yousaf": ["Woolly Sheep", Color(0.95, 0.93, 0.88), ["", Color(0, 0, 0), Color(0, 0, 0, 0), 1.0], Color(0.15, 0.13, 0.13),
		[["wool_head", Color(0.97, 0.95, 0.9)], ["wool_body", Color(0.97, 0.95, 0.9)], ["ears_side", Color(0.2, 0.17, 0.17)], ["ram_horns", Color(0.75, 0.62, 0.45)]]],
}


static func _mascot_outfit(id: String, female: bool) -> Dictionary:
	var d: Array = MASCOT[id]
	var suit: Color = d[1]
	var pt: Array = d[2]
	var t := {c = suit, sat = 0.0, bright = 0.62}
	if String(pt[0]) != "":
		t.pat = {kind = pt[0], a = pt[1], b = pt[2], scale = pt[3]}
	var opt: Dictionary = d[5] if d.size() > 5 else {}
	var legs: Color = opt.get("legs", suit)
	var tint := {"Hair": "hide", "Tie": "hide", "Tops": t, "Bottoms": {c = legs, sat = 0.0, bright = 0.6}, "Shoes": {c = d[3], sat = 0.0, bright = 0.6}}
	var acc: Array = []
	for base in [["kig_hood", suit], ["suit_body", suit], ["suit_arms", suit], ["suit_legs", legs], ["suit_paws", d[3]]]:
		if not base[0] in opt.get("skip", []): acc.append(base)
	acc.append_array((d[4] as Array).duplicate(true))
	return {name = d[0], tint = tint, acc = acc}


static func _persona_outfit(id: String, hair: Dictionary, female: bool, kind: String) -> Dictionary:
	var d: Array = PERSONA[id]
	var top: Array = d[1]
	var tint := {"Hair": "hide" if kind == "hijab" else hair, "Tie": "hide"}
	var t := {c = top[0], sat = 0.0, bright = 0.62}
	if String(top[1]) != "":
		t.pat = {kind = top[1], a = top[2], b = top[3], scale = top[4]}
	else:
		t.c = Color.WHITE; t.pat = {kind = "solid", a = top[0]}
	tint.merge({"Tops": t, "Bottoms": {c = d[2], sat = 0.0, bright = 0.6}, "Shoes": {c = d[3], sat = 0.0, bright = 0.6}}, true)
	var parts: Array = (d[4] as Array).duplicate(true)
	# the women's base wears shorts: cover the legs when the look doesn't already
	if female and not parts.any(func(x): return x[0] == "shalwar"): parts.append(["shalwar", d[2]])
	return {name = d[0], tint = tint, acc = parts}


static func _extra_outfit(k: int, kind: String, acc: Color, hair: Dictionary, female: bool) -> Dictionary:
	var T := func(c: Color, bright := 0.75) -> Dictionary: return {c = c, sat = 0.0, bright = bright}
	var S := func(c: Color, bright := 0.75, pat := {}) -> Dictionary:
		return {c = Color.WHITE, sat = 0.0, bright = bright, pat = pat if not pat.is_empty() else {kind = "solid", a = c}}
	var dark := Color(0.12, 0.11, 0.14)
	var hijab := kind == "hijab"
	var tint := {"Hair": "hide" if hijab else hair, "Tie": "hide"}
	var parts: Array = []
	match k:
		3:   # Fight Night: dark tee, accent trousers, hand wraps, belt and headband
			tint.merge({"Tops": S.call(dark, 0.55), "Bottoms": T.call(acc.darkened(0.25), 0.6), "Shoes": T.call(Color(0.1, 0.1, 0.11), 0.35)}, true)
			parts.append_array([["wraps", Color(0.92, 0.9, 0.86)], ["belt", acc]])
			if not hijab: parts.append(["headband", acc])
		4:   # Hacker Hoodie: dark hoodie with a glowing tech grid in their colour, headphones
			tint.merge({"Tops": {c = Color(0.3, 0.3, 0.36), sat = 0.0, bright = 0.42, pat = {kind = "grid", a = acc.lightened(0.15), b = acc.lightened(0.45), scale = 1.0}},
				"Bottoms": T.call(Color(0.16, 0.2, 0.32), 0.5), "Shoes": T.call(Color(0.92, 0.92, 0.94), 0.85)}, true)
			parts.append_array([["hood", Color(0.22, 0.22, 0.26)], ["sleeves", Color(0.22, 0.22, 0.26)]])
			if not hijab: parts.append(["headphones", Color(0.1, 0.1, 0.12)])
		5:   # Eid Special: kurta / embroidered kameez with a dupatta
			var cream := Color(0.95, 0.92, 0.84)
			tint.merge({"Tops": S.call(cream, 0.8), "Bottoms": T.call(cream, 0.75), "Shoes": T.call(Color(0.5, 0.32, 0.15), 0.55)}, true)
			if female:
				parts.append_array([["kameez", acc], ["shalwar", cream], ["sleeves", acc], ["dupatta", Color(1.0, 0.8, 0.35)]])
			else:
				parts.append_array([["kameez", cream], ["shalwar", cream], ["sleeves", cream]])
			if hijab: parts.append(["hijab", acc.lightened(0.2)])
	if hijab and k != 5: parts.append_array([["hijab", acc], ["sleeves", Color(0.2, 0.2, 0.24)]])
	if female and k != 5: parts.append(["shalwar", Color(0.18, 0.18, 0.22) if k == 3 else Color(0.16, 0.2, 0.32)])
	return {tint = tint, acc = parts}


static func _hair(desc: String, female: bool) -> Dictionary:
	var d := desc.to_lower()
	var c := Color(0.16, 0.13, 0.12)
	if "brown" in d: c = Color(0.42, 0.28, 0.18)
	elif "blond" in d: c = Color(0.95, 0.8, 0.45)
	elif "red" in d: c = Color(0.7, 0.2, 0.12)
	elif "grey" in d or "gray" in d: c = Color(0.7, 0.7, 0.72)
	return {c = c, sat = 0.3, bright = 0.5 if not female else 0.55}


static var LIST := {
	"vex": {file = SEED, costumes = [
		{name = "Prototype", tint = {"huku": {c = Color(0.95, 0.97, 1.0), sat = 1.0, bright = 0.78}}, acc = [["visor", Color(0.18, 0.9, 1.0)]]},
		{name = "Crimson Unit", tint = {"hair": {c = Color(0.9, 0.25, 0.3), sat = 0.0, bright = 1.0}, "huku": {c = Color(0.85, 0.38, 0.4), sat = 0.0, bright = 0.75}, "green_emit": Color(1.0, 0.3, 0.3)},
			acc = [["visor", Color(1.0, 0.25, 0.3)], ["shoulders", Color(0.25, 0.08, 0.1)]]},
		{name = "Stealth", tint = {"huku": {c = Color(0.35, 0.37, 0.42), sat = 0.0, bright = 0.6}, "hair": {c = Color(0.85, 0.85, 0.9), sat = 0.0, bright = 1.2}},
			acc = [["visor", Color(0.6, 1.0, 0.4)], ["kneepads", Color(0.12, 0.13, 0.15)]]},
	]},
	"sora": {file = GIRL, costumes = [
		{name = "Dobok", tint = {
			"Tops": {c = Color(0.92, 0.93, 0.96), sat = 0.0, bright = 0.74}, "Bottoms": Color(0.3, 0.33, 0.75),
			"Hair": {c = Color(0.22, 0.22, 0.28), sat = 0.2, bright = 0.55}, "Shoes": {c = Color(0.92, 0.92, 0.94), sat = 0.0, bright = 0.95}}.merged(skin(Color(0.86, 0.72, 0.64))),
			acc = [["headband", Color(0.45, 0.95, 0.6)], ["belt", Color(0.08, 0.08, 0.1)]]},
		{name = "Street", tint = {
			"Tops": {c = Color(0.55, 0.57, 0.62), sat = 0.0, bright = 0.75}, "Bottoms": Color(0.35, 0.45, 0.7),
			"Hair": {c = Color(0.55, 0.35, 0.25), sat = 0.6, bright = 0.7}, "Shoes": Color(1.0, 0.4, 0.4)}.merged(skin(Color(0.86, 0.72, 0.64))),
			acc = [["wraps", Color(0.95, 0.95, 0.95)]]},
		{name = "Champion", tint = {
			"Tops": Color(1.0, 0.3, 0.3), "Bottoms": {c = Color(0.25, 0.25, 0.28), sat = 0.0, bright = 0.5},
			"Hair": {c = Color(0.22, 0.22, 0.28), sat = 0.2, bright = 0.55}}.merged(skin(Color(0.86, 0.72, 0.64))),
			acc = [["headband", Color(1.0, 0.25, 0.25)], ["belt", Color(1.0, 0.8, 0.25)]]},
	]},
	"ember": {file = GIRL, costumes = [
		{name = "Luchadora", tint = {
			"Tops": Color(0.7, 0.3, 1.0), "Bottoms": Color(0.55, 0.22, 0.85),
			"Hair": {c = Color(1.0, 0.42, 0.25), sat = 1.6, bright = 1.3}, "Shoes": Color(1.0, 0.82, 0.3)}.merged(skin(Color(0.8, 0.62, 0.5))),
			acc = [["belt", Color(1.0, 0.75, 0.2)], ["wraps", Color(1.0, 0.55, 0.15)], ["kneepads", Color(0.55, 0.2, 0.85)]]},
		{name = "Inferno", tint = {
			"Tops": Color(1.0, 0.3, 0.18), "Bottoms": {c = Color(0.2, 0.2, 0.22), sat = 0.0, bright = 0.45},
			"Hair": {c = Color(1.0, 0.85, 0.35), sat = 1.2, bright = 1.2}, "Shoes": {c = Color(0.2, 0.2, 0.2), sat = 0.0, bright = 0.4}}.merged(skin(Color(0.8, 0.62, 0.5))),
			acc = [["belt", Color(0.15, 0.15, 0.15)], ["wraps", Color(1.0, 0.35, 0.15)], ["kneepads", Color(1.0, 0.35, 0.15)]]},
		{name = "Gala", tint = {
			"Tops": {c = Color(0.95, 0.95, 1.0), sat = 0.0, bright = 0.72}, "Bottoms": {c = Color(0.95, 0.95, 1.0), sat = 0.0, bright = 0.85},
			"Hair": {c = Color(1.0, 0.42, 0.25), sat = 1.6, bright = 1.3}, "Shoes": Color(1.0, 0.82, 0.3)}.merged(skin(Color(0.8, 0.62, 0.5))),
			acc = [["belt", Color(1.0, 0.8, 0.3)], ["sash", Color(1.0, 0.8, 0.3)]]},
	]},
	"mara": {file = GIRL, costumes = [
		{name = "Title Fight", tint = {
			"Tops": Color(1.0, 0.22, 0.28), "Bottoms": Color(1.0, 0.25, 0.25),
			"Hair": {c = Color(0.35, 0.3, 0.3), sat = 0.5, bright = 0.55}}.merged(skin(Color(0.6, 0.42, 0.32))),
			acc = [["gloves", Color(0.9, 0.12, 0.15)], ["belt", Color(1.0, 0.8, 0.25)]]},
		{name = "Gold Belt", tint = {
			"Tops": {c = Color(0.25, 0.25, 0.28), sat = 0.0, bright = 0.45}, "Bottoms": Color(1.0, 0.8, 0.3),
			"Hair": {c = Color(0.35, 0.3, 0.3), sat = 0.5, bright = 0.55}}.merged(skin(Color(0.6, 0.42, 0.32))),
			acc = [["gloves", Color(1.0, 0.78, 0.2)], ["belt", Color(1.0, 0.85, 0.3)]]},
		{name = "Training", tint = {
			"Tops": {c = Color(0.7, 0.72, 0.76), sat = 0.0, bright = 0.8}, "Bottoms": Color(0.3, 0.4, 0.8),
			"Hair": {c = Color(0.35, 0.3, 0.3), sat = 0.5, bright = 0.55}}.merged(skin(Color(0.6, 0.42, 0.32))),
			acc = [["gloves", Color(0.2, 0.4, 0.95)], ["headband", Color(0.95, 0.95, 0.95)]]},
	]},
	"bastion": {file = MALE, costumes = [
		{name = "Dock Brawler", tint = {
			"Tops": Color(0.75, 0.16, 0.16), "Tie": "hide",
			"Bottoms": {c = Color(0.55, 0.6, 0.7), sat = 0.2, bright = 0.8}, "Shoes": Color(0.45, 0.3, 0.2),
			"Hair": {c = Color(0.3, 0.27, 0.25), sat = 0.4, bright = 0.45}}.merged(skin(Color(0.62, 0.45, 0.34))),
			acc = [["wraps", Color(0.12, 0.12, 0.12)], ["belt", Color(1.0, 0.45, 0.15)]]},
		{name = "Hi-Vis", tint = {
			"Tops": Color(1.0, 0.6, 0.12), "Tie": "hide",
			"Bottoms": Color(0.25, 0.3, 0.45), "Shoes": Color(0.3, 0.22, 0.15),
			"Hair": {c = Color(0.3, 0.27, 0.25), sat = 0.4, bright = 0.45}}.merged(skin(Color(0.62, 0.45, 0.34))),
			acc = [["wraps", Color(0.9, 0.9, 0.9)], ["kneepads", Color(0.15, 0.15, 0.15)]]},
		{name = "Night Shift", tint = {
			"Tops": Color(0.2, 0.28, 0.5), "Tie": "hide",
			"Bottoms": {c = Color(0.2, 0.2, 0.22), sat = 0.0, bright = 0.5}, "Shoes": Color(0.2, 0.15, 0.12),
			"Hair": {c = Color(0.3, 0.27, 0.25), sat = 0.4, bright = 0.45}}.merged(skin(Color(0.62, 0.45, 0.34))),
			acc = [["wraps", Color(0.15, 0.35, 0.8)], ["shoulders", Color(0.12, 0.14, 0.2)]]},
	]},
	"lio": {file = MALE, costumes = [
		{name = "Roda", tint = {
			"Tops": Color(0.35, 0.85, 0.5), "Tie": "hide",
			"Bottoms": {c = Color(1, 1, 1), sat = 0.0, bright = 1.0}, "Shoes": {c = Color(0.9, 0.9, 0.9), sat = 0.0, bright = 0.95},
			"Hair": {c = Color(0.55, 0.4, 0.28), sat = 0.8, bright = 0.6}}.merged(skin(Color(0.8, 0.6, 0.45))),
			acc = [["sash", Color(0.25, 0.85, 0.45)]]},
		{name = "Carnival", tint = {
			"Tops": Color(1.0, 0.85, 0.2), "Tie": "hide",
			"Bottoms": Color(0.25, 0.45, 1.0), "Shoes": Color(1.0, 0.85, 0.2),
			"Hair": {c = Color(0.55, 0.4, 0.28), sat = 0.8, bright = 0.6}}.merged(skin(Color(0.8, 0.6, 0.45))),
			acc = [["sash", Color(1.0, 0.85, 0.2)], ["headband", Color(0.25, 0.45, 1.0)]]},
		{name = "Mestre", tint = {
			"Tops": {c = Color(1, 1, 1), sat = 0.0, bright = 0.95}, "Tie": "hide",
			"Bottoms": {c = Color(1, 1, 1), sat = 0.0, bright = 1.0}, "Shoes": {c = Color(1, 1, 1), sat = 0.0, bright = 0.95},
			"Hair": {c = Color(0.8, 0.8, 0.82), sat = 0.0, bright = 1.0}}.merged(skin(Color(0.7, 0.52, 0.38))),
			acc = [["sash", Color(0.75, 0.35, 0.95)], ["armbands", Color(0.75, 0.35, 0.95)]]},
	]},
	"tao": {file = MALE, costumes = [
		{name = "Iron Monk", tint = {
			"Tops": Color(0.72, 0.12, 0.1), "Tie": "hide",
			"Bottoms": {c = Color(0.3, 0.3, 0.32), sat = 0.0, bright = 0.45}, "Shoes": {c = Color(0.3, 0.3, 0.3), sat = 0.0, bright = 0.35},
			"Hair": {c = Color(1, 1, 1.04), sat = 0.0, bright = 1.3}}.merged(skin(Color(0.95, 0.8, 0.68))),
			acc = [["sash", Color(0.95, 0.75, 0.3)], ["wraps", Color(0.95, 0.75, 0.3)]]},
		{name = "Jade", tint = {
			"Tops": Color(0.2, 0.65, 0.45), "Tie": "hide",
			"Bottoms": {c = Color(0.3, 0.3, 0.32), sat = 0.0, bright = 0.4}, "Shoes": {c = Color(0.3, 0.3, 0.3), sat = 0.0, bright = 0.35},
			"Hair": {c = Color(1, 1, 1.04), sat = 0.0, bright = 1.3}}.merged(skin(Color(0.95, 0.8, 0.68))),
			acc = [["sash", Color(0.1, 0.1, 0.1)], ["armbands", Color(0.95, 0.75, 0.3)]]},
		{name = "Ink", tint = {
			"Tops": {c = Color(0.2, 0.2, 0.22), sat = 0.0, bright = 0.35}, "Tie": "hide",
			"Bottoms": {c = Color(1, 1, 1), sat = 0.0, bright = 0.9}, "Shoes": {c = Color(0.3, 0.3, 0.3), sat = 0.0, bright = 0.35},
			"Hair": {c = Color(1, 1, 1.04), sat = 0.0, bright = 1.3}}.merged(skin(Color(0.95, 0.8, 0.68))),
			acc = [["sash", Color(0.85, 0.15, 0.15)], ["wraps", Color(0.9, 0.9, 0.9)]]},
	]},
	"kael": {file = MALE, costumes = [
		{name = "Stadium", tint = {
			"Tops": Color(0.95, 0.25, 0.3), "Tie": "hide",
			"Bottoms": Color(0.25, 0.4, 1.0), "Shoes": {c = Color(1, 1, 1), sat = 0.0, bright = 0.95},
			"Hair": {c = Color(0.3, 0.28, 0.28), sat = 0.3, bright = 0.4}}.merged(skin(Color(0.82, 0.62, 0.46))),
			acc = [["headband", Color(0.9, 0.15, 0.2)], ["wraps", Color(0.95, 0.95, 0.95)], ["armbands", Color(0.9, 0.15, 0.2)]]},
		{name = "Gold Shorts", tint = {
			"Tops": {c = Color(0.25, 0.25, 0.28), sat = 0.0, bright = 0.45}, "Tie": "hide",
			"Bottoms": Color(1.0, 0.78, 0.25), "Shoes": {c = Color(1, 1, 1), sat = 0.0, bright = 0.95},
			"Hair": {c = Color(0.3, 0.28, 0.28), sat = 0.3, bright = 0.4}}.merged(skin(Color(0.82, 0.62, 0.46))),
			acc = [["headband", Color(1.0, 0.8, 0.3)], ["wraps", Color(1.0, 0.8, 0.3)], ["armbands", Color(0.15, 0.15, 0.15)]]},
		{name = "Black Tiger", tint = {
			"Tops": {c = Color(0.2, 0.2, 0.22), sat = 0.0, bright = 0.35}, "Tie": "hide",
			"Bottoms": {c = Color(0.2, 0.2, 0.22), sat = 0.0, bright = 0.35}, "Shoes": {c = Color(0.3, 0.3, 0.3), sat = 0.0, bright = 0.4},
			"Hair": {c = Color(0.3, 0.28, 0.28), sat = 0.3, bright = 0.4}}.merged(skin(Color(0.82, 0.62, 0.46))),
			acc = [["headband", Color(1.0, 0.55, 0.1)], ["wraps", Color(1.0, 0.55, 0.1)], ["kneepads", Color(0.15, 0.15, 0.15)]]},
	]},
}
