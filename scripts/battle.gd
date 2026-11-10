class_name Battle
extends RefCounted
## A sea fight in 1-second ticks on open water under a steady wind.
## Pure logic: the 3D view and the headless tests both just call step().
##
## Coordinates are metres on a plane, x east / y north. Headings are radians
## with direction (cos h, sin h). wind_from is the direction the wind blows
## FROM, so a ship heading straight into it is "in irons" and stops.

const DECIDE_EVERY := 4.0          # seconds between captains' decisions
const LOOKAHEAD := 40.0            # seconds a captain looks ahead when steering
const MAX_TIME := 3.0 * 3600.0     # about the daylight left when a sail is sighted
const LOSE_SIGHT := 3500.0         # metres: hull-down and gone
const GRAPPLE := 18.0
const KNOT := 0.5144
const ARC := 0.45                  # radians either side of the beam a broadside bears
const RANGE := {"round": 700.0, "chain": 350.0, "grape": 220.0}
const WANT := {"close": 70.0, "long": 330.0}
## Seconds to reload a broadside with a full gun crew.
const RELOAD := {"Navy": 120.0, "Pirate": 140.0, "Privateer": 150.0, "Trader": 260.0,
	"navy": 120.0, "pirate": 140.0, "privateer": 150.0, "merchant": 280.0}
## Hand-to-hand quality: pirates and privateers shipped big crews to board.
const MELEE := {"Navy": 1.1, "Pirate": 1.2, "Privateer": 1.1, "Trader": 0.7,
	"navy": 1.1, "pirate": 1.2, "privateer": 1.1, "merchant": 0.7}

var rng: RandomNumberGenerator
var wind_from := 0.0
var t := 0.0
var ships: Array = []              # [player, enemy]
var events: Array = []             # for the view: {type, ...}; the view drains it
var lines: Array[String] = []      # battle log
var outcome := ""                  # "" while fighting
var grappled := false
var _grapple_clock := 0.0
var _decide_clock := 0.0
var _check_clock := 0.0
var _closest := INF
var _closest_t := 0.0

## p / e: {ship (dict), crew, morale, kind ("Trader".. or "merchant".."navy"),
##         orders {mode, range, shot, board, ram}, traits, label, nation, pirate}
func setup(p: Dictionary, e: Dictionary, r: RandomNumberGenerator) -> void:
	rng = r
	wind_from = rng.randf_range(-PI, PI)
	var d := rng.randf_range(1100.0, 1700.0)
	var bearing := rng.randf_range(-PI, PI)
	ships = [_make(p, Vector2.ZERO, 0), _make(e, Vector2(cos(bearing), sin(bearing)) * d, 1)]
	# Both are on passage when they sight each other: start on sailable courses.
	for sh in ships:
		sh["heading"] = _best_course(sh, sh["heading"])
		sh["desired"] = sh["heading"]
		sh["speed"] = _target_speed(sh, sh["heading"]) * 0.8

func _make(d: Dictionary, pos: Vector2, idx: int) -> Dictionary:
	var c: Dictionary = World.SHIPS[d["ship"]["cls"]]
	var sh := d.duplicate()
	sh["idx"] = idx
	sh["pos"] = pos
	sh["heading"] = rng.randf_range(-PI, PI)
	sh["speed"] = 0.0
	sh["knots"] = float(c["knots"])
	sh["rig_type"] = c["rig"]
	sh["length"] = float(c["length"])
	sh["min_off"] = deg_to_rad(45.0) if c["rig"] == "fore_aft" else deg_to_rad(65.0)
	sh["turn"] = deg_to_rad(5.0) if c["rig"] == "fore_aft" else deg_to_rad(3.0)
	sh["crew0"] = int(d["crew"])
	sh["reload"] = [rng.randf_range(0.0, 30.0), rng.randf_range(0.0, 30.0)]   # port, starboard
	sh["struck"] = false
	sh["sunk"] = false
	sh["repelled"] = false
	sh["rammed"] = false
	sh["shots_fired"] = 0
	sh["hits_made"] = 0
	sh["killed"] = 0
	return sh

func player() -> Dictionary:
	return ships[0]

func enemy() -> Dictionary:
	return ships[1]

func distance() -> float:
	return ships[0]["pos"].distance_to(ships[1]["pos"])

func done() -> bool:
	return outcome != ""

func say(msg: String) -> void:
	var m := int(t / 60.0)
	lines.append("%d:%02d  %s" % [m / 60, m % 60, msg])

# ------------------------------------------------------------------ sailing

func _off_wind(h: float) -> float:
	return absf(wrapf(h - wind_from, -PI, PI))

## Fraction of best speed on a heading. Square-riggers run well before the
## wind; fore-and-aft rigs point higher but run less well.
func _polar(sh: Dictionary, h: float) -> float:
	var off := _off_wind(h)
	var mn: float = sh["min_off"]
	if off < mn:
		return 0.12 * off / mn
	var peak := deg_to_rad(100.0)
	if off <= peak:
		return 0.55 + 0.45 * smoothstep(mn, peak, off)
	var run := 0.95 if sh["rig_type"] == "square" else 0.78
	return lerpf(1.0, run, (off - peak) / (PI - peak))

func _target_speed(sh: Dictionary, h: float) -> float:
	var s: Dictionary = sh["ship"]
	var manning: float = clamp(float(sh["crew"]) / (float(s["crew_cap"]) * 0.35), 0.3, 1.0)
	var rig: float = clamp(float(s["rig"]) / 100.0, 0.1, 1.0)
	return float(sh["knots"]) * KNOT * _polar(sh, h) * rig * manning * (0.0 if sh["struck"] else 1.0)

## Nearest heading to h that isn't in irons.
func _best_course(sh: Dictionary, h: float) -> float:
	var off := wrapf(h - wind_from, -PI, PI)
	var mn: float = sh["min_off"] + 0.05
	if absf(off) >= mn:
		return h
	return wind_from + (mn if off >= 0.0 else -mn)

func _vel(sh: Dictionary) -> Vector2:
	return Vector2(cos(sh["heading"]), sin(sh["heading"])) * float(sh["speed"])

# ------------------------------------------------------------------ captains

## Utility steering: try 24 headings, score where each leaves us in LOOKAHEAD
## seconds against what our orders want, pick the best.
func _decide(sh: Dictionary) -> void:
	var other: Dictionary = ships[1 - int(sh["idx"])]
	var o: Dictionary = sh["orders"]
	if sh["idx"] == 1 and o["mode"] == "engage" and float(other["ship"]["hull"]) < float(other["ship"]["hull_max"]) * 0.3 \
			and int(sh["crew"]) > int(other["crew"]) and not sh["repelled"]:
		# She's beaten: close and take her rather than sink a prize.
		o["mode"] = "board"
		o["shot"] = "grape"
		o["board"] = true
	var mode: String = o["mode"]
	var p2: Vector2 = other["pos"] + _vel(other) * LOOKAHEAD
	var best := -INF
	var best_h: float = sh["heading"]
	for i in 18:
		var h := float(i) / 18.0 * TAU
		var v := _target_speed(sh, h)
		var p1: Vector2 = sh["pos"] + Vector2(cos(h), sin(h)) * v * LOOKAHEAD
		var d := p1.distance_to(p2)
		var u := 0.0
		match mode:
			"flee":
				u = d / 100.0 + v * 0.3
			"board", "ram":
				u = -d / 50.0
				if mode == "ram":
					var to := (p2 - p1).angle()
					u -= absf(wrapf(h - to, -PI, PI)) * 2.0
			_:   # engage at a range, broadside on
				var want: float = WANT[o.get("range", "close")]
				u = -absf(d - want) / 100.0
				if d < want + 250.0:
					var rel := absf(wrapf((p2 - p1).angle() - h, -PI, PI))
					u += (1.0 - absf(rel - PI / 2.0) / (PI / 2.0)) * 2.5
		u -= absf(wrapf(h - float(sh["heading"]), -PI, PI)) * 0.15   # don't thrash the helm
		if u > best:
			best = u
			best_h = h
	sh["desired"] = best_h

func _steer(sh: Dictionary, dt: float) -> void:
	var err := wrapf(float(sh["desired"]) - float(sh["heading"]), -PI, PI)
	var rate: float = float(sh["turn"]) * clamp(float(sh["speed"]) / 2.0, 0.35, 1.0)
	sh["heading"] = wrapf(float(sh["heading"]) + clamp(err, -rate * dt, rate * dt), -PI, PI)
	var target := _target_speed(sh, sh["heading"])
	sh["speed"] = float(sh["speed"]) + (target - float(sh["speed"])) * (0.06 if target > float(sh["speed"]) else 0.1) * dt
	sh["pos"] = sh["pos"] + _vel(sh) * dt

# ------------------------------------------------------------------ guns

func _fire(sh: Dictionary, dt: float) -> void:
	var other: Dictionary = ships[1 - int(sh["idx"])]
	if sh["struck"] or other["struck"] or other["sunk"]:
		return
	var d := distance()
	var shot: String = sh["orders"].get("shot", "round")
	var maxr: float = RANGE[shot]
	var guns_side := int(int(sh["ship"]["guns"]) / 2)
	var manning: float = clamp(float(sh["crew"]) / max(1.0, guns_side * 4.0), 0.25, 1.0)
	var bearing: float = (other["pos"] - sh["pos"]).angle()
	var rel := wrapf(bearing - float(sh["heading"]), -PI, PI)
	for side in 2:   # 0 = port (left, +90°), 1 = starboard (right, −90°)
		sh["reload"][side] = maxf(0.0, float(sh["reload"][side]) - dt)
		var beam := PI / 2.0 if side == 0 else -PI / 2.0
		if absf(wrapf(rel - beam, -PI, PI)) > ARC or d > maxr or float(sh["reload"][side]) > 0.0:
			continue
		if sh.get("powder", 999.0) <= 0.0:
			continue
		if sh.has("powder"):
			sh["powder"] = float(sh["powder"]) - guns_side * 0.0025
		var quality: float = 1.0 if RELOAD[sh["kind"]] <= 120.0 else (0.9 if RELOAD[sh["kind"]] <= 150.0 else 0.65)
		var p_hit: float = clamp(0.8 * pow(1.0 - d / maxr, 1.2) * quality * (0.6 + 0.4 * manning), 0.03, 0.85)
		var hits := 0
		for g in guns_side:
			if rng.randf() < p_hit:
				hits += 1
		var hull := 0.0
		var rig := 0.0
		var kills := 0.0
		match shot:
			"round":
				hull = hits * 2.2
				rig = hits * 0.4
				kills = hits * 0.3
			"chain":
				rig = hits * 3.5
				hull = hits * 0.3
				kills = hits * 0.1
			"grape":
				kills = hits * (1.3 if d < 120.0 else 0.6)
				hull = hits * 0.2
				rig = hits * 0.3
		var k := int(floor(kills + rng.randf()))
		k = min(k, int(other["crew"]))
		other["ship"]["hull"] = float(other["ship"]["hull"]) - hull
		other["ship"]["rig"] = maxf(5.0, float(other["ship"]["rig"]) - rig)
		other["crew"] = int(other["crew"]) - k
		var shock: float = k * 100.0 / max(1.0, float(other["crew0"])) * 0.7 + hull * 0.25 + rig * 0.05
		other["morale"] = maxf(0.0, float(other["morale"]) - shock)
		sh["shots_fired"] = int(sh["shots_fired"]) + guns_side
		sh["hits_made"] = int(sh["hits_made"]) + hits
		sh["killed"] = int(sh["killed"]) + k
		sh["reload"][side] = float(RELOAD[sh["kind"]]) / manning * rng.randf_range(0.85, 1.15)
		events.append({"type": "broadside", "from": sh["idx"], "side": side, "guns": guns_side, "hits": hits,
			"shot": shot, "target": other["pos"], "dist": d})
		say("%s a %s broadside of %s: %d of %d hit%s." % ["You fire" if sh["idx"] == 0 else "She fires", "port" if side == 0 else "starboard",
			shot, hits, guns_side, (", %d killed" % k) if k > 0 else ""])

func _name(sh: Dictionary) -> String:
	return "You" if sh["idx"] == 0 else "She"

# ------------------------------------------------------------------ ram & board

func _close_quarters() -> void:
	var a: Dictionary = ships[0]
	var b: Dictionary = ships[1]
	var d := distance()
	if grappled:
		return
	for sh in [a, b]:
		var other: Dictionary = ships[1 - int(sh["idx"])]
		var o: Dictionary = sh["orders"]
		if sh["struck"] or other["struck"]:
			continue
		if o.get("ram", false) and not sh["rammed"] and d < float(sh["length"]) * 0.5 + 8.0:
			var to: float = (other["pos"] - sh["pos"]).angle()
			var closing: float = (_vel(sh) - _vel(other)).dot((other["pos"] - sh["pos"]).normalized())
			if absf(wrapf(to - float(sh["heading"]), -PI, PI)) < 0.6 and closing > 0.8:
				var ratio: float = sqrt(float(sh["ship"]["hull_max"]) / float(other["ship"]["hull_max"]))
				var dmg: float = closing * 6.0 * ratio
				other["ship"]["hull"] = float(other["ship"]["hull"]) - dmg
				sh["ship"]["hull"] = float(sh["ship"]["hull"]) - dmg * 0.6 / ratio
				sh["ship"]["rig"] = maxf(10.0, float(sh["ship"]["rig"]) - 8.0)
				other["morale"] = maxf(0.0, float(other["morale"]) - 10.0)
				sh["rammed"] = true
				events.append({"type": "ram", "from": sh["idx"]})
				say("%s ram%s at %.1f knots! Hull -%d, and the ships lock together." % [_name(sh),
					"" if sh["idx"] == 0 else "s you", closing / KNOT, dmg])
				_grapple(sh)
				return
		if (o.get("board", false) or o["mode"] == "board") and not sh["repelled"] and d < GRAPPLE:
			_grapple(sh)
			return

func _grapple(attacker: Dictionary) -> void:
	grappled = true
	_grapple_clock = 0.0
	attacker["boarding"] = true
	for sh in ships:
		sh["speed"] = 0.0
	events.append({"type": "grapple", "from": attacker["idx"]})
	say("%s throw%s the grapnels and board%s!" % [_name(attacker), "" if attacker["idx"] == 0 else "s",
		"" if attacker["idx"] == 0 else "s you"])

## One round of hand-to-hand every 20 seconds while the hulls are locked.
func _melee() -> void:
	var att: Dictionary = ships[0] if ships[0].get("boarding", false) else ships[1]
	var dfn: Dictionary = ships[1 - int(att["idx"])]
	var bonus := 1.15 if att["rammed"] else 1.0
	var sa: float = float(att["crew"]) * (0.5 + float(att["morale"]) / 100.0) * float(MELEE[att["kind"]]) * bonus
	var sd: float = float(dfn["crew"]) * (0.5 + float(dfn["morale"]) / 100.0) * float(MELEE[dfn["kind"]]) * 1.25
	var share: float = sa / max(1.0, sa + sd)
	var att_loss := int(round(float(att["crew"]) * 0.08 * (1.0 - share) * rng.randf_range(0.6, 1.4)))
	var dfn_loss := int(round(float(dfn["crew"]) * 0.10 * share * rng.randf_range(0.6, 1.4)))
	att["crew"] = max(0, int(att["crew"]) - att_loss)
	dfn["crew"] = max(0, int(dfn["crew"]) - dfn_loss)
	att["morale"] = maxf(0.0, float(att["morale"]) - att_loss * 100.0 / max(1.0, float(att["crew0"])) - (4.0 if share < 0.5 else 0.0))
	dfn["morale"] = maxf(0.0, float(dfn["morale"]) - dfn_loss * 100.0 / max(1.0, float(dfn["crew0"])) - (4.0 if share > 0.5 else 0.0))
	events.append({"type": "melee", "att": att["idx"], "att_loss": att_loss, "dfn_loss": dfn_loss})
	if float(dfn["morale"]) < 15.0 or int(dfn["crew"]) < max(2, int(float(dfn["crew0"]) * 0.3)):
		dfn["struck"] = true
		say("%s carried the deck. %s" % ["You" if att["idx"] == 0 else "They", "She is yours!" if att["idx"] == 0 else "Your ship is taken."])
		_finish("prize" if att["idx"] == 0 else "boarded_lost")
	elif float(att["morale"]) < 20.0 or int(att["crew"]) < max(2, int(float(att["crew0"]) * 0.3)):
		att["repelled"] = true
		att["boarding"] = false
		att["orders"]["board"] = false
		if att["orders"]["mode"] == "board":
			att["orders"]["mode"] = "engage"
		grappled = false
		say("%s beaten back and the grapnels are cut." % ("Your boarders are" if att["idx"] == 0 else "Her boarders are"))
		events.append({"type": "repelled", "att": att["idx"]})

# ------------------------------------------------------------------ yielding

func _check_strike() -> void:
	for sh in ships:
		if sh["struck"]:
			continue
		var hp: float = float(sh["ship"]["hull"]) / float(sh["ship"]["hull_max"])
		if hp <= 0.0:
			sh["sunk"] = true
			say("%s going down!" % ("You are" if sh["idx"] == 0 else "She is"))
			events.append({"type": "sunk", "idx": sh["idx"]})
			_finish("we_sank" if sh["idx"] == 0 else "sunk_them")
			return
		var yields := false
		if sh["idx"] == 0:
			# Your crew yield when their spirit breaks, or rather than drown —
			# unless they're pirates facing a navy and the rope.
			var noose: bool = sh["kind"] == "Pirate" and enemy()["kind"] == "navy"
			yields = float(sh["morale"]) < 10.0 or int(sh["crew"]) < max(2, int(float(sh["crew0"]) * 0.15)) \
				or (hp < 0.1 and not noose)
		else:
			var caution: float = sh.get("traits", {}).get("caution", 0.4)
			yields = hp < 0.2 + 0.25 * caution or float(sh["morale"]) < 15.0 or int(sh["crew"]) < max(2, int(float(sh["crew0"]) * 0.25))
		if yields:
			sh["struck"] = true
			events.append({"type": "strike", "idx": sh["idx"]})
			say("Your crew strike the colours!" if sh["idx"] == 0 else "She strikes her colours!")
			_finish("we_struck" if sh["idx"] == 0 else "prize")
			return

## Most merchantmen struck when a stronger ship ran them down and showed its
## colours: resistance meant no quarter. Call when the attacker closes in.
func hopeless(sh: Dictionary, attacker: Dictionary, pirate: bool) -> bool:
	var ours := Sim.power(sh["ship"], int(sh["crew"]), float(sh["morale"]))
	var theirs := Sim.power(attacker["ship"], int(attacker["crew"]), float(attacker["morale"]))
	var ratio: float = theirs / max(1.0, ours) * (1.3 if pirate else 1.0)
	var caution: float = sh.get("traits", {}).get("caution", 0.5)
	var p: float = clamp((ratio - 1.0) * 0.45 * (0.4 + caution), 0.0, 0.92)
	return rng.randf() < p

func _finish(o: String) -> void:
	if outcome == "":
		outcome = o
		events.append({"type": "end", "outcome": o})

# ------------------------------------------------------------------ tick

func step(dt: float = 1.0) -> void:
	if done():
		return
	t += dt
	_decide_clock -= dt
	if _decide_clock <= 0.0:
		_decide_clock = DECIDE_EVERY
		for sh in ships:
			if not grappled and not sh["struck"]:
				_decide(sh)
	if not grappled:
		for sh in ships:
			_steer(sh, dt)
		_close_quarters()
	for sh in ships:
		_fire(sh, dt)
	if grappled:
		_grapple_clock += dt
		if _grapple_clock >= 20.0:
			_grapple_clock = 0.0
			_melee()
	if done():
		return
	_check_clock -= dt
	if _check_clock <= 0.0:
		_check_clock = 10.0
		_check_strike()
		if done():
			return
		# A merchant run down by a stronger ship gives up once in close range.
		var e := enemy()
		if e["kind"] == "merchant" and not e.get("asked", false) and distance() < 350.0 \
				and player()["orders"]["mode"] != "flee":
			e["asked"] = true
			if hopeless(e, player(), player()["kind"] == "Pirate"):
				e["struck"] = true
				say("She lets fly her sheets and strikes her colours without a fight.")
				events.append({"type": "strike", "idx": 1})
				_finish("prize")
				return
		var d := distance()
		# A stern chase that isn't closing: the chaser gives it up.
		if d < _closest - 25.0:
			_closest = d
			_closest_t = t
		var chased := enemy() if enemy()["orders"]["mode"] == "flee" else (player() if player()["orders"]["mode"] == "flee" else {})
		if not chased.is_empty() and d > 600.0 and t - _closest_t > 1800.0:
			say("Half an hour without gaining a cable: %s." % ("she has the legs of you" if chased["idx"] == 1 else "she can't catch you"))
			_finish("escaped" if chased["idx"] == 1 else "we_escaped")
			return
		if d > LOSE_SIGHT:
			say("Hull-down and gone.")
			_finish("escaped" if enemy()["orders"]["mode"] == "flee" else "we_escaped")
			return
	if t >= MAX_TIME:
		say("Night falls and the ships lose each other in the dark.")
		_finish("stalemate")

## You haul down your colours.
func player_strikes() -> void:
	if done():
		return
	ships[0]["struck"] = true
	say("You strike your colours.")
	events.append({"type": "strike", "idx": 0})
	_finish("we_struck")

## Run to the end (headless).
func run() -> String:
	while not done():
		step(3.0 if distance() > 1200.0 and not grappled else 1.0)
	return outcome
