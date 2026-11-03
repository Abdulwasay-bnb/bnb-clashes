# Prompt for the Claude browser extension: collect Mixamo animations for BNB Clashes

Copy everything below the line into the Claude extension while you are logged in at https://www.mixamo.com.

---

You're helping me collect animations from Mixamo (mixamo.com, I'm already logged in) for my 3D fighting game,
"BNB Clashes". The game has 8 original fighters, each with a different martial art. Mixamo's names won't
match what I ask for exactly, so I need you to **use your judgment**: preview the candidates, then pick the
clip that best fits each slot below. Some slots ask for 2–3 options. Quality and believability matter more
than finding an exact name match.

## Download settings (use these for EVERY animation)
- Character: the default **Y Bot**. Don't change the character, so every clip shares one skeleton.
- In the download dialog:
  - Format: **FBX Binary (.fbx)**
  - Skin: **Without Skin**
  - Frames per second: **30**
  - Keyframe reduction: **none**
- If the clip has an **"In Place"** checkbox, **tick it**. My game moves the fighter itself.
- Before downloading, leave the sliders (Overdrive, Character Arm-Space, Trim) at their defaults, unless a
  clip is obviously broken without a tweak. If you change one, say so in the report.
- **First download only:** one reference file of Y Bot **With Skin** (search "T-Pose"). Name it `_reference_tpose`.

## How to pick (your judgment)
- Prefer **clean, single, readable** motions over long combos. Exception: slots marked *combo* or *finisher*.
- Prefer **fighting stance / combat** versions over casual ones, e.g. a fighting idle rather than a relaxed idle.
- For attacks, prefer clips where the hit lands roughly **0.3–0.8 s** into the clip. Very slow wind-ups
  feel bad in a fighting game.
- Skip clips with props (swords, guns), sitting, swimming, or dance moves, unless the slot asks for them.
- Avoid near-duplicates. If two candidates are basically the same, keep the better-looking one.
- If nothing fits a slot well, skip it and write **"no good match"** in the report. Don't force it.

## Slots
Rename each file to the slot name if the browser lets you choose a filename. If it doesn't, keep Mixamo's
name and just list the mapping in the report. `[x2]` / `[x3]` means pick that many different options, named
`_a`, `_b`, `_c`.

### 1. Core movement & reactions (shared by everyone)
| slot | what I need |
|---|---|
| idle_fight [x3] | fighting-stance idle: a boxing idle, a martial-arts idle, a relaxed brawler idle |
| walk_forward [x2] | stepping forward in a guard, not a casual walk |
| walk_back [x2] | stepping backward in a guard |
| strafe_left / strafe_right | sidestep or strafe while guarding |
| dash_forward | quick forward burst / lunge step |
| backdash | quick hop or step back |
| crouch_idle | crouched guard |
| block_high / block_low | blocking a head-level hit / a low hit (crouch block if available) |
| hit_head [x2] | getting punched in the face / head snap |
| hit_body [x2] | getting hit in the stomach / doubling over |
| hit_heavy | big stagger from a heavy blow |
| knockdown [x2] | knocked down onto the back (falling flat) |
| launched | knocked up into the air / flying backwards |
| getup [x2] | getting up from lying on the back |
| ko | knocked out (falls and stays down) |
| thrown | being grabbed and thrown / falling hard |
| throw | grabbing someone and throwing or slamming them |

### 2. Strikes (shared library; I map these to each fighter's moves)
| slot | what I need |
|---|---|
| jab [x2] | quick lead-hand punch |
| cross [x2] | straight rear-hand punch |
| hook [x2] | hook punch (one left, one right if possible) |
| uppercut [x2] | rising uppercut |
| body_punch | punch to the body / liver |
| overhand | big overhead looping punch |
| elbow [x2] | elbow strike (horizontal and/or rising) |
| knee [x2] | knee strike (straight; a flying knee if found) |
| front_kick / push_kick | front snap kick / teep (push kick) |
| roundhouse [x3] | roundhouse kick: low, body and head height if available |
| side_kick | side kick |
| spinning_kick [x2] | spinning back / heel kick, hurricane-style kick |
| axe_kick | leg rises high and drops down |
| low_kick / leg_sweep | low kick to the legs, and a sweep along the ground |
| jump_kick [x2] | jumping / flying kick |
| headbutt | headbutt |
| palm_strike | open-palm strike (kung fu style) |

### 3. Style-specific (one list per fighter; these make each character feel different)
- **Mara (boxer):** boxing idle with head movement, slipping or weaving, a boxing combo *(combo)*, a
  haymaker or bolo punch.
- **Kael (Muay Thai):** Muay Thai stance or bounce, a clinch knee, a spinning elbow, a body kick.
- **Lio (capoeira):** ginga (capoeira sway), a cartwheel kick (aú), meia lua / armada spinning kicks, a
  handstand. Mixamo has a capoeira set, so use it generously.
- **Sora (taekwondo / kickboxer):** fast kick combos *(combo)*, a 540 / tornado-style kick, a kick-heavy
  fighting stance.
- **Tao (kung fu):** a kung-fu stance, chain punches or palm strikes, a crane or martial-arts pose, a
  "martial arts" combo *(combo)*.
- **Ember (luchadora / wrestler):** a wrestling grapple, a suplex or slam, a dropkick, a body slam,
  a lariat / clothesline.
- **Bastion (heavy brawler):** heavy brawler punches, a shoulder charge / tackle, a ground pound or
  double-fist smash, a headbutt.
- **VEX-9 (android):** anything mechanical or robotic-feeling: a precise stiff jab, robotic idle, power
  punch.

### 4. Showpieces
| slot | what I need |
|---|---|
| intro [x6] | match-start poses: bow, taunt, stretching / warming up, fist bump, salute, flex |
| victory [x6] | win poses: victory, cheering, fist pump, taunt, celebration |
| finisher [x4] | flashy power moves for super attacks: spinning combo, flying kick, big uppercut or knockout punch, a multi-hit kick flurry |
| taunt [x2] | taunting gestures |
| defeated | sad / defeated pose for the loser |

## Report back (very important)
When you're done, or if you hit a limit, reply with a **table** with these columns:

`slot | Mixamo name (exact) | downloaded filename | duration (s) | approx impact time (s) | notes`

- **Impact time** is when the punch or kick fully extends. For non-attacks write `-`.
- In **notes**, mention anything special: it travels forward a lot, has no In Place option, a slider changed, etc.

Also add:
- A list of slots you skipped, with the reason.
- Any **extra clips you found that would look great** in a fighting game but don't fit a slot (up to 10).
  Download them too and name them `extra_<short name>`.

Target: roughly **90–130 downloads**. Pace yourself if Mixamo rate-limits you, and if downloads stop
working, stop and report what you have so far.
