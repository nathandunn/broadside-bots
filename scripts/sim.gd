class_name Sim
extends RefCounted
## All the rules for v0: voyage days, events, markets, encounters and
## auto-resolved combat. Static functions over a GameState so the same
## code drives the UI and a headless test/sim run.

const PACE_NM := {"easy": 70.0, "steady": 100.0, "crowd": 130.0}
const RATION := {"full": 1.0, "half": 0.6, "short": 0.35}
const HEALTH_BY_RATION := {"full": 0.4, "half": -0.2, "short": -0.8}
const MORALE_BY_RATION := {"full": 0.2, "half": -0.5, "short": -1.5}
const FOOD_PER_MAN := 0.0025     # tons per man-day at full rations
const WATER_PER_MAN := 0.004
const RUM_PER_MAN := 0.0008
const MEDICINE_PER_DAY := 0.002
const WAGE_PER_MAN_DAY := 0.19   # ~25 shillings a month ≈ 5.5 pieces of eight (merchant seamen, 1670s)
const SCURVY_DAYS := 42          # ~6 weeks without fresh food
const MONTHS := [["Jan", 31], ["Feb", 28], ["Mar", 31], ["Apr", 30], ["May", 31], ["Jun", 30],
	["Jul", 31], ["Aug", 31], ["Sep", 30], ["Oct", 31], ["Nov", 30], ["Dec", 31]]
const MARKET_BASE_STOCK := 80.0

# ------------------------------------------------------------------ setup

static func new_game(role: String, seed: int = 0) -> GameState:
	var s := GameState.new()
	if seed == 0:
		s.rng.randomize()
	else:
		s.rng.seed = seed
	s.role = role
	for n in World.NATIONS:
		s.reputation[n] = 0
	if role == "Pirate":
		s.ship = make_ship("sloop", "Revenge")
		s.crew = 50
		s.chest = 300.0
		s.morale = 60.0
		s.bounty = 200.0
		s.infamy = 10.0
		s.location = "st_thomas"
		s.stores = {"food": 3.0, "water": 5.0, "powder": 3.0, "spares": 2.0, "medicine": 0.1}
		s.cargo = {}
		for n in World.NATIONS:
			if n != "Denmark":
				s.reputation[n] = -20
		s.rum_ration = true
	else:
		s.role = "Trader"
		s.ship = make_ship("fluyt", "Good Hope")
		s.crew = 18
		s.chest = 1500.0
		s.location = "bridgetown"
		s.stores = {"food": 2.0, "water": 3.0, "powder": 1.0, "spares": 2.0, "medicine": 0.2}
		s.cargo = {"sugar": 20.0}
	_init_markets(s)
	s.say("%s %s takes command of the %s %s at %s." % [s.role, s.captain_name,
		s.ship["name"], s.ship["label"], World.port_by_id(s.location)["name"]])
	return s

static func make_ship(cls: String, label: String) -> Dictionary:
	var c: Dictionary = World.SHIPS[cls]
	return {"cls": cls, "name": c["name"], "label": label,
		"hull": float(c["hull"]), "hull_max": float(c["hull"]), "rig": 100.0,
		"guns": int(c["guns"]), "crew_cap": int(c["crew_cap"]),
		"cargo": float(c["cargo"]), "speed": float(c["speed"])}

static func _init_markets(s: GameState) -> void:
	for p in World.PORTS:
		var m := {}
		for g in World.GOODS:
			m[g] = _target_stock(p, g) * s.rng.randf_range(0.8, 1.2)
		s.markets[p["id"]] = m

static func _target_stock(p: Dictionary, g: String) -> float:
	if g in p["produces"]:
		return MARKET_BASE_STOCK * 2.0
	if g in p["wants"]:
		return MARKET_BASE_STOCK * 0.5
	return MARKET_BASE_STOCK

## Each day, every market drifts 3% back toward its natural stock.
static func tick_markets(s: GameState) -> void:
	for p in World.PORTS:
		var m: Dictionary = s.markets[p["id"]]
		for g in m:
			var target := _target_stock(p, g)
			m[g] = float(m[g]) + (target - float(m[g])) * 0.03

# ------------------------------------------------------------------ calendar

static func date_string(s: GameState) -> String:
	var d := s.day % 365
	var y := World.START_YEAR + int(s.day / 365)
	for m in MONTHS:
		if d < int(m[1]):
			return "%d %s %d" % [d + 1, m[0], y]
		d -= int(m[1])
	return "%d" % y

static func in_hurricane_season(s: GameState) -> bool:
	var d := s.day % 365
	return d >= 151 and d <= 333   # June through November

# ------------------------------------------------------------------ markets

static func price(s: GameState, port_id: String, good: String) -> float:
	var stock: float = s.markets[port_id][good]
	var base: float = World.GOODS[good]["base"]
	var f := pow(MARKET_BASE_STOCK / max(stock, 5.0), 0.7)
	return base * clamp(f, 0.4, 2.5)

## Price with the market's stock shifted by delta tons (for averaging over a lot).
static func _price_at(s: GameState, port_id: String, good: String, delta: float) -> float:
	var stock: float = float(s.markets[port_id][good]) + delta
	var base: float = World.GOODS[good]["base"]
	return base * clamp(pow(MARKET_BASE_STOCK / max(stock, 5.0), 0.7), 0.4, 2.5)

static func lot_buy_cost(s: GameState, port_id: String, good: String, tons: float) -> float:
	return _price_at(s, port_id, good, -tons / 2.0) * 1.05 * tons

static func lot_sell_value(s: GameState, port_id: String, good: String, tons: float) -> float:
	var v := _price_at(s, port_id, good, tons / 2.0) * 0.95 * tons
	if World.port_by_id(port_id)["haven"]:
		v *= 0.6
	return v

static func buy_price(s: GameState, port_id: String, good: String) -> float:
	return price(s, port_id, good) * 1.05

static func sell_price(s: GameState, port_id: String, good: String) -> float:
	var p := price(s, port_id, good) * 0.95
	if World.port_by_id(port_id)["haven"]:
		p *= 0.6   # fence: no questions asked, poor prices
	return p

static func buy_good(s: GameState, good: String, tons: float) -> String:
	if s.at_sea():
		return "You are at sea."
	tons = min(tons, s.cargo_free())
	if tons <= 0.0:
		return "The hold is full."
	var cost := lot_buy_cost(s, s.location, good, tons)
	while cost > s.chest and tons > 0.0:
		tons = floor(tons * min(0.9, s.chest / cost))
		cost = lot_buy_cost(s, s.location, good, tons)
	if tons <= 0.0:
		return "Not enough coin."
	s.chest -= cost
	s.cargo[good] = float(s.cargo.get(good, 0.0)) + tons
	s.markets[s.location][good] = max(5.0, float(s.markets[s.location][good]) - tons)
	return "Bought %d t of %s for %d." % [tons, World.GOODS[good]["name"], cost]

static func sell_good(s: GameState, good: String, tons: float) -> String:
	if s.at_sea():
		return "You are at sea."
	tons = min(tons, float(s.cargo.get(good, 0.0)))
	if tons <= 0.0:
		return "None aboard."
	var got := lot_sell_value(s, s.location, good, tons)
	s.chest += got
	s.cargo[good] = float(s.cargo[good]) - tons
	if float(s.cargo[good]) <= 0.001:
		s.cargo.erase(good)
	s.markets[s.location][good] = float(s.markets[s.location][good]) + tons
	return "Sold %d t of %s for %d." % [tons, World.GOODS[good]["name"], got]

static func store_price(s: GameState, store: String) -> float:
	var p: float = World.STORES[store]["price"]
	if s.role == "Pirate":
		p *= 1.3
	return p

static func buy_store(s: GameState, store: String, tons: float) -> String:
	if s.at_sea():
		return "You are at sea."
	tons = min(tons, s.cargo_free())
	var unit := store_price(s, store)
	tons = min(tons, floor(s.chest / unit * 10.0) / 10.0)
	if tons <= 0.0:
		return "No room or no coin."
	s.chest -= unit * tons
	s.stores[store] = float(s.stores.get(store, 0.0)) + tons
	return "Took on %.1f t of %s." % [tons, World.STORES[store]["name"]]

static func days_of(s: GameState, store: String) -> float:
	var per := FOOD_PER_MAN if store == "food" else WATER_PER_MAN
	var need: float = s.crew * per * float(RATION[s.rations])
	if need <= 0.0:
		return 999.0
	return float(s.stores.get(store, 0.0)) / need

static func recruit(s: GameState, n: int) -> String:
	if s.at_sea():
		return "You are at sea."
	var port := World.port_by_id(s.location)
	if s.role == "Pirate" and not port["haven"]:
		return "No honest tavern will sign on for a pirate."
	n = min(n, int(s.ship["crew_cap"]) - s.crew)
	var each := 0.0 if s.role == "Pirate" else 6.0   # a month's advance
	if each > 0.0:
		n = min(n, int(s.chest / each))
	if n <= 0:
		return "No room or no coin."
	s.chest -= each * n
	s.crew += n
	return "Signed on %d hands." % n

static func pay_wages(s: GameState) -> String:
	var amt: float = min(s.pay_owed, s.chest)
	if amt <= 0.0:
		return "Nothing owed." if s.pay_owed <= 0.0 else "The chest is empty."
	s.chest -= amt
	s.pay_owed -= amt
	s.morale = min(100.0, s.morale + 15.0 * amt / max(1.0, amt + s.pay_owed))
	return "Paid %d in wages." % amt

static func repair_cost(s: GameState) -> float:
	return (float(s.ship["hull_max"]) - float(s.ship["hull"])) * 8.0 + (100.0 - float(s.ship["rig"])) * 6.0

static func repair(s: GameState) -> String:
	if s.at_sea():
		return "You are at sea."
	var cost := repair_cost(s)
	if cost <= 0.0:
		return "She's sound."
	if cost > s.chest:
		return "The shipwright wants %d; you haven't got it." % cost
	s.chest -= cost
	s.ship["hull"] = s.ship["hull_max"]
	s.ship["rig"] = 100.0
	return "Repaired for %d." % cost

## Trader: move profits from the ship's chest to the captain's own purse.
static func bank(s: GameState, amt: float) -> String:
	if s.at_sea():
		return "You are at sea."
	if s.role == "Pirate":
		return "Pirates share out; they don't bank."
	amt = min(amt, s.chest)
	s.chest -= amt
	s.purse += amt
	return "Banked %d." % amt

## Trader: draw from the purse back into the ship's chest.
static func withdraw(s: GameState, amt: float) -> String:
	if s.at_sea():
		return "You are at sea."
	amt = min(amt, s.purse)
	if amt <= 0.0:
		return "Your purse is empty."
	s.purse -= amt
	s.chest += amt
	return "Drew %d from your purse." % amt

## Pirate: share out the plunder by the articles. Captain 2 shares, each hand 1.
static func share_out(s: GameState) -> String:
	if s.at_sea() or not World.port_by_id(s.location)["haven"]:
		return "Plunder is shared out ashore, in a haven."
	# The articles set aside a common fund for the ship before the shares.
	var keep: float = min(s.chest, 500.0 + s.chest * 0.3)
	var pot := s.chest - keep
	if pot <= 0.0:
		return "Nothing to share."
	var share := pot / float(s.crew + 2)
	s.purse += share * 2.0
	s.chest = keep
	s.morale = min(100.0, s.morale + clamp(share / 4.0, 5.0, 40.0))
	s.days_since_plunder = 0
	return "Shared out %d: %d a man, %d for the captain." % [pot, share, share * 2.0]

## Days ashore: the crew eat fresh, sleep and drink. Wages still run.
static func rest(s: GameState, days: int) -> String:
	if s.at_sea():
		return "You are at sea."
	for i in days:
		s.day += 1
		s.age += 1.0 / 365.0
		tick_markets(s)
		s.health = min(100.0, s.health + 3.0)
		s.morale = min(100.0, s.morale + (2.0 if s.morale < 70.0 else 0.2))
		# Careen and patch her yourselves: slower than a shipwright, but free.
		if float(s.ship["hull"]) < float(s.ship["hull_max"]):
			var fix := 1.5
			if float(s.stores.get("spares", 0.0)) >= 0.1:
				s.stores["spares"] = float(s.stores["spares"]) - 0.1
				fix = 5.0
			s.ship["hull"] = min(float(s.ship["hull_max"]), float(s.ship["hull"]) + fix)
			s.ship["rig"] = min(100.0, float(s.ship["rig"]) + fix)
		if s.role == "Trader":
			s.pay_owed += s.crew * WAGE_PER_MAN_DAY
	return "Rested %d days ashore%s." % [days, ", careening and patching her" if float(s.ship["hull"]) < float(s.ship["hull_max"]) else ""]

# ------------------------------------------------------------------ voyage

static func can_sail_to(s: GameState, port_id: String) -> String:
	var p := World.port_by_id(port_id)
	if p.is_empty():
		return "No such port."
	if port_id == s.location:
		return "You're already there. (Use Cruise to hunt the sea lanes and come back.)"
	if s.role == "Pirate" and not p["haven"]:
		return "The fort at %s would sink a pirate on sight." % p["name"]
	if s.crew < int(ceil(int(s.ship["crew_cap"]) * 0.15)):
		return "Too few hands to work the ship."
	return ""

static func set_sail(s: GameState, port_id: String) -> String:
	var why := can_sail_to(s, port_id)
	if why != "":
		return why
	var a := World.port_by_id(s.location)
	var b := World.port_by_id(port_id)
	s.voyage = {"from": s.location, "to": port_id, "total_nm": World.distance_nm(a, b), "done_nm": 0.0}
	s.location = ""
	s.say("Weighed anchor for %s, %d leagues off." % [b["name"], s.voyage["total_nm"] / 3.0])
	var need := World.distance_nm(a, b) / (float(PACE_NM[s.pace]) * float(s.ship["speed"]) * 0.95) * 1.5
	if days_of(s, "food") < need or days_of(s, "water") < need:
		s.say("The purser frets: stores may not last the passage.")
	return ""

## Go "on the account": cruise the lanes for some days and return to this port.
static func cruise(s: GameState, days: int) -> String:
	if s.at_sea():
		return "Already at sea."
	if s.crew < int(ceil(int(s.ship["crew_cap"]) * 0.15)):
		return "Too few hands to work the ship."
	var nm := float(PACE_NM[s.pace]) * float(s.ship["speed"]) * 0.95 * days
	s.voyage = {"from": s.location, "to": s.location, "total_nm": nm, "done_nm": 0.0, "cruise": true}
	var here: String = World.port_by_id(s.location)["name"]
	s.location = ""
	s.say("Put out from %s to cruise the sea lanes for some %d days." % [here, days])
	return ""

## Cut a cruise short and run back to the home port.
static func head_home(s: GameState) -> String:
	if not s.at_sea() or not s.voyage.get("cruise", false):
		return "Not on a cruise."
	var done: float = s.voyage["done_nm"]
	var back: float = min(done, float(s.voyage["total_nm"]) - done)
	s.voyage["total_nm"] = done + min(back, 160.0)
	s.say("Put about and made for %s." % World.port_by_id(s.voyage["to"])["name"])
	return ""

static func est_days(s: GameState, port_id: String) -> float:
	var from := World.port_by_id(s.location) if not s.at_sea() else World.port_by_id(s.voyage["from"])
	var nm := World.distance_nm(from, World.port_by_id(port_id))
	return nm / (float(PACE_NM[s.pace]) * float(s.ship["speed"]) * 0.95)

## Advance one day at sea. Returns an event {type, text} or {} for a quiet day.
static func sail_day(s: GameState) -> Dictionary:
	if s.ended or not s.at_sea() or not s.encounter.is_empty():
		return {}
	s.day += 1
	s.age += 1.0 / 365.0
	tick_markets(s)
	s.days_since_fresh += 1
	s.days_since_plunder += 1
	var r: float = RATION[s.rations]
	var dh := 0.0
	var dm := 0.0

	# Food and water
	var starving := false
	for st in ["food", "water"]:
		var per := FOOD_PER_MAN if st == "food" else WATER_PER_MAN
		var need := s.crew * per * r
		var have: float = s.stores.get(st, 0.0)
		if have >= need:
			s.stores[st] = have - need
		else:
			s.stores[st] = 0.0
			starving = true
	if starving:
		dh -= 5.0
		dm -= 4.0
	else:
		dh += float(HEALTH_BY_RATION[s.rations])
		dm += float(MORALE_BY_RATION[s.rations])

	# Rum
	if s.rum_ration:
		var rum_need := s.crew * RUM_PER_MAN
		if s.cargo.has("rum") and float(s.cargo["rum"]) >= rum_need:
			s.cargo["rum"] = float(s.cargo["rum"]) - rum_need
			dm += 0.4

	# Scurvy
	if s.days_since_fresh > SCURVY_DAYS:
		if float(s.stores.get("medicine", 0.0)) >= MEDICINE_PER_DAY:
			s.stores["medicine"] = float(s.stores["medicine"]) - MEDICINE_PER_DAY
			dh -= 0.6
		else:
			dh -= 1.2

	# Pace
	if s.pace == "crowd":
		dh -= 0.3
		dm -= 0.3
		s.ship["rig"] = max(20.0, float(s.ship["rig"]) - 0.4)
	elif s.pace == "easy":
		dh += 0.2
		dm += 0.2

	# Pay and plunder
	if s.role == "Trader":
		s.pay_owed += s.crew * WAGE_PER_MAN_DAY
		if s.pay_owed > s.crew * 7.0:
			dm -= 0.5
	elif s.days_since_plunder > 30:
		dm -= 0.4

	s.health = clamp(s.health + dh, 0.0, 100.0)
	s.morale = clamp(s.morale + dm, 0.0, 100.0)

	# Carpenter patches the hull from spares
	if float(s.ship["hull"]) < float(s.ship["hull_max"]) and float(s.stores.get("spares", 0.0)) >= 0.05:
		s.stores["spares"] = float(s.stores["spares"]) - 0.05
		s.ship["hull"] = min(float(s.ship["hull_max"]), float(s.ship["hull"]) + 2.0)

	# Deaths
	var p_die: float = 0.0003 + max(0.0, 60.0 - s.health) / 60.0 * 0.01
	var dead := 0
	for i in s.crew:
		if s.rng.randf() < p_die:
			dead += 1
	if dead > 0:
		s.crew -= dead
		s.say("%d %s buried at sea." % [dead, "man" if dead == 1 else "men"])
	if s.crew <= 0:
		return _end(s, "Your last hand is dead. The %s drifts, a ghost ship." % s.ship["label"])
	if s.age >= 50.0 and s.rng.randf() < (s.age - 50.0) * 0.00005:
		return _end(s, "Captain %s died in his cot, aged %d." % [s.captain_name, s.age])

	# Distance
	var manning: float = clamp(float(s.crew) / (float(s.ship["crew_cap"]) * 0.4), 0.3, 1.0)
	var nm: float = float(PACE_NM[s.pace]) * float(s.ship["speed"]) * s.rng.randf_range(0.6, 1.3) \
		* (float(s.ship["rig"]) / 100.0) * manning

	# One event a day at most
	var ev := {}
	var storm_p := 0.025 * (3.0 if in_hurricane_season(s) else 1.0) * (1.5 if s.pace == "crowd" else 1.0)
	var roll := s.rng.randf()
	if s.morale < 15.0 and s.rng.randf() < 0.08:
		ev = _mutiny(s)
		if s.ended:
			return ev
	elif s.morale < 30.0 and s.rng.randf() < 0.1:
		ev = {"type": "grumbling", "text": "Grumbling on the lower deck. Mind the morale, Captain."}
	elif roll < storm_p:
		var dmg := s.rng.randf_range(5.0, 25.0)
		s.ship["hull"] = float(s.ship["hull"]) - dmg
		s.ship["rig"] = max(10.0, float(s.ship["rig"]) - s.rng.randf_range(5.0, 20.0))
		var lost := int(s.rng.randf() < 0.3) * s.rng.randi_range(1, 3)
		s.crew = max(0, s.crew - lost)
		nm *= 0.3
		ev = {"type": "storm", "text": "A storm! Hull -%d%s." % [dmg, (", %d washed overboard" % lost) if lost > 0 else ""]}
		if float(s.ship["hull"]) <= 0.0:
			return _end(s, "The %s foundered in the storm with all hands." % s.ship["label"])
	elif roll < storm_p + 0.04:
		nm = 0.0
		ev = {"type": "becalmed", "text": "Becalmed. Not a breath of wind."}
	elif roll < storm_p + 0.055:
		var hit := 4.0 if float(s.stores.get("medicine", 0.0)) >= 0.02 else 10.0
		if hit == 4.0:
			s.stores["medicine"] = float(s.stores["medicine"]) - 0.02
		s.health = max(0.0, s.health - hit)
		ev = {"type": "sickness", "text": "Fever below decks. Health -%d." % hit}
	elif roll < storm_p + 0.055 + (0.07 if s.role == "Pirate" else 0.06):
		s.encounter = make_encounter(s)
		ev = {"type": "encounter", "text": s.encounter["text"]}

	s.voyage["done_nm"] = float(s.voyage["done_nm"]) + nm
	if ev.has("text"):
		s.say(ev["text"])
	if s.encounter.is_empty() and float(s.voyage["done_nm"]) >= float(s.voyage["total_nm"]):
		return arrive(s)
	return ev

static func _mutiny(s: GameState) -> Dictionary:
	if s.role == "Trader" and s.chest >= s.pay_owed and s.pay_owed > 0.0:
		s.chest -= s.pay_owed
		s.pay_owed = 0.0
		s.morale = 35.0
		return {"type": "mutiny", "text": "The crew mutinied over wages. You paid them off from the chest to keep your ship."}
	var e := _end(s, "Mutiny! The crew seized the %s and marooned you on a sandbar." % s.ship["label"])
	return e

static func arrive(s: GameState) -> Dictionary:
	var to: String = s.voyage["to"]
	var p := World.port_by_id(to)
	s.location = to
	s.voyage = {}
	s.days_since_fresh = 0
	s.health = min(100.0, s.health + 5.0)
	var text := "Dropped anchor at %s." % p["name"]
	if s.morale < 40.0:
		var gone := int(s.crew * (40.0 - s.morale) / 200.0)
		if gone > 0:
			s.crew -= gone
			text += " %d deserted ashore." % gone
	if s.role == "Trader" and s.pay_owed > 0.0 and s.chest > 0.0:
		text += " " + pay_wages(s)
	s.say(text)
	return {"type": "landfall", "text": text}

static func _end(s: GameState, why: String) -> Dictionary:
	s.alive = false
	s.ended = true
	s.end_reason = why
	s.say(why)
	return {"type": "death", "text": why}

# ------------------------------------------------------------------ encounters

static func _nearest_nation(s: GameState) -> String:
	var a := World.port_by_id(s.voyage.get("from", s.location))
	var b := World.port_by_id(s.voyage.get("to", s.location))
	var t: float = 0.0
	if s.voyage.has("total_nm") and float(s.voyage["total_nm"]) > 0.0:
		t = float(s.voyage["done_nm"]) / float(s.voyage["total_nm"])
	return b["nation"] if t > 0.5 else a["nation"]

static func power(ship: Dictionary, crew: int, morale: float) -> float:
	var manning: float = clamp(float(crew) / max(1.0, float(ship["guns"]) * 4.0), 0.2, 1.0)
	return (float(ship["guns"]) * manning * 3.0 + crew * 0.6) * (float(ship["hull"]) / float(ship["hull_max"])) * (0.5 + morale / 100.0)

static func flag(s: GameState) -> String:
	return "" if s.role == "Pirate" else "England"

static func make_encounter(s: GameState) -> Dictionary:
	var nation := _nearest_nation(s)
	if nation == "Denmark" or s.voyage.get("cruise", false):
		nation = ["England", "France", "Dutch", "Spain"][s.rng.randi_range(0, 3)]
	var roll := s.rng.randf()
	# Navies were thin in the West Indies; most sails were merchants.
	var kind := "merchant" if roll < 0.62 else ("navy" if roll < 0.74 else "pirate")
	var cls := ""
	var pers := ""
	match kind:
		"merchant":
			cls = "fluyt" if s.rng.randf() < 0.6 else "merchantman"
			pers = "Cautious merchant" if s.rng.randf() < 0.6 else "Stubborn merchant"
		"navy":
			cls = "frigate" if s.rng.randf() < 0.3 else "brigantine"
			pers = "Dutiful navy"
		_:
			cls = "sloop" if s.rng.randf() < 0.65 else "brigantine"
			pers = "Greedy pirate" if s.rng.randf() < 0.55 else "Bloodthirsty pirate"
			nation = "Pirate"
	var ship := make_ship(cls, "")
	var crew_frac: float = {"merchant": 0.7, "navy": 0.9, "pirate": 0.85}[kind]
	var crew := int(int(ship["crew_cap"]) * crew_frac * s.rng.randf_range(0.8, 1.1))
	var traits: Dictionary = World.PERSONALITIES[pers]
	var morale: float = {"merchant": 45.0, "navy": 75.0, "pirate": 55.0 + 30.0 * float(traits["aggression"])}[kind]
	var cargo := {}
	var coin := 0.0
	if kind == "merchant":
		var goods := World.GOODS.keys()
		var left: float = float(ship["cargo"]) * s.rng.randf_range(0.4, 0.8)
		for i in 3:
			var g: String = goods[s.rng.randi_range(0, goods.size() - 1)]
			var t: float = left / (3 - i) if g != "silver" else min(left / (3 - i), 4.0)
			cargo[g] = float(cargo.get(g, 0.0)) + t
			left -= t
		coin = s.rng.randf_range(200.0, 1500.0)
	elif kind == "navy":
		coin = s.rng.randf_range(100.0, 400.0)
	else:
		coin = s.rng.randf_range(500.0, 3000.0)
		if s.rng.randf() < 0.3:
			cargo["silver"] = s.rng.randf_range(1.0, 3.0)

	var ours := power(s.ship, s.crew, s.morale)
	var theirs := power(ship, crew, morale)
	var hostile := false
	match kind:
		"pirate":
			hostile = s.rng.randf() < float(traits["aggression"]) and theirs / max(1.0, ours) > float(traits["caution"]) * 1.2
			if s.role == "Pirate" and pers != "Bloodthirsty pirate":
				hostile = false   # pirates seldom preyed on each other
		"navy":
			var cause := s.role == "Pirate" or s.bounty > 500.0 or World.at_war(nation, flag(s))
			hostile = cause and s.rng.randf() < float(traits["aggression"])
	var adj: String = {"England": "an English", "France": "a French", "Dutch": "a Dutch", "Spain": "a Spanish"}.get(nation, "a")
	var who := "%s %s" % [adj, ship["name"].to_lower()] if kind != "pirate" else "a pirate %s" % ship["name"].to_lower()
	if kind == "navy":
		who = "%s navy %s" % [adj, ship["name"].to_lower()]
	var text := "Sail ho! %s, %d guns, ~%d men (%s)." % [who.substr(0, 1).to_upper() + who.substr(1), ship["guns"], crew, pers]
	text += " She's bearing down on us!" if hostile else (" She keeps her distance." if kind != "merchant" else " A fat merchant.")
	return {"kind": kind, "nation": nation, "ship": ship, "crew": crew, "morale": morale,
		"personality": pers, "traits": traits, "hostile": hostile, "cargo": cargo, "coin": coin, "text": text}

## Player's answer to an encounter. action: sail_on | flee | trade | attack | surrender
static func resolve(s: GameState, action: String, orders: Dictionary = {}) -> Dictionary:
	var e: Dictionary = s.encounter
	if e.is_empty():
		return {"text": "Nothing in sight."}
	var res := {}
	match action:
		"sail_on":
			if e["hostile"]:
				res = _chase(s, e, orders, 0.0)
			else:
				res = {"text": "She passes astern. You hold your course."}
		"flee":
			res = _chase(s, e, orders, 0.15) if e["hostile"] else {"text": "You crowd on sail and leave her behind."}
		"trade":
			if e["hostile"] or e["kind"] != "merchant":
				res = {"text": "She won't heave to for you."}
			else:
				res = _trade_at_sea(s, e)
		"attack":
			_turn_pirate_if_lawless(s, e)
			res = combat(s, e, orders)
		"surrender":
			res = _surrender(s, e)
		_:
			res = {"text": "?"}
	s.encounter = {}
	if res.has("text") and not s.ended:
		s.say(res["text"])
	return res

static func _speed(ship: Dictionary) -> float:
	return float(ship["speed"]) * float(ship["rig"]) / 100.0

static func _chase(s: GameState, e: Dictionary, orders: Dictionary, bonus: float) -> Dictionary:
	var ours := _speed(s.ship) * (1.15 if s.pace == "crowd" else 1.0)
	var theirs := _speed(e["ship"])
	var shoal := 0.15 if s.ship["cls"] == "sloop" and e["ship"]["cls"] in ["frigate", "merchantman"] else 0.0   # shallow draft: run over the shoals
	var p: float = clamp(0.45 + (ours - theirs) * 2.0 + bonus + shoal + s.rng.randf_range(-0.15, 0.15), 0.05, 0.95)
	if s.rng.randf() < p:
		return {"text": "You show her your heels and get clean away."}
	var r := combat(s, e, orders)
	if not s.ended:
		r["text"] = "She ran you down. " + r["text"]
	return r

static func _trade_at_sea(s: GameState, e: Dictionary) -> Dictionary:
	var got := ""
	for st in ["food", "water"]:
		var t: float = min(1.0, s.cargo_free())
		var cost: float = float(World.STORES[st]["price"]) * 1.5 * t
		if t > 0.0 and cost <= s.chest:
			s.chest -= cost
			s.stores[st] = float(s.stores.get(st, 0.0)) + t
			got += " %.0f t %s" % [t, World.STORES[st]["name"].to_lower()]
	return {"text": "Traded for stores at sea:%s." % (got if got != "" else " nothing")}

static func _turn_pirate_if_lawless(s: GameState, e: Dictionary) -> void:
	if s.role == "Pirate" or e["kind"] == "pirate":
		return
	if World.at_war(flag(s), e["nation"]):
		return
	s.role = "Pirate"
	s.bounty += 500.0
	s.infamy += 10.0
	s.reputation[e["nation"]] = int(s.reputation[e["nation"]]) - 40
	for n in World.NATIONS:
		if n != "Denmark" and n != e["nation"]:
			s.reputation[n] = int(s.reputation[n]) - 10
	s.pay_owed = 0.0
	s.say("You've fired on a ship of a nation at peace. You are a pirate now — no lawful port will have you.")

static func _surrender(s: GameState, e: Dictionary) -> Dictionary:
	if not e["hostile"]:
		return {"text": "She has no quarrel with you."}
	if e["kind"] == "navy" and s.role == "Pirate":
		return _end(s, "Taken by the %s navy. Tried at the Admiralty court and hanged at low-water mark." % e["nation"])
	var took := s.chest * 0.5
	s.chest -= took
	s.cargo = {}
	s.morale = max(0.0, s.morale - 25.0)
	return {"text": "You strike your colours. They strip the hold and take %d from the chest, then let you go." % took}

# ------------------------------------------------------------------ combat

## Auto-resolved fight. orders: {range: close|long, shot: round|chain|grape, board: bool, ram: bool}
static func combat(s: GameState, e: Dictionary, orders: Dictionary) -> Dictionary:
	var o := {"range": "close", "shot": "round", "board": true, "ram": false}
	o.merge(orders, true)
	var us := {"ship": s.ship, "crew": s.crew, "morale": s.morale, "crew0": s.crew}
	var them := {"ship": e["ship"].duplicate(), "crew": int(e["crew"]), "morale": float(e["morale"]), "crew0": int(e["crew"])}
	var tr: Dictionary = e["traits"]
	var their_range := "long" if e["kind"] == "merchant" else ("close" if e["kind"] == "pirate" else ("long" if s.rng.randf() < 0.5 else "close"))
	var their_shot := "chain" if e["kind"] == "merchant" else ("grape" if e["kind"] == "pirate" else "round")
	var lines: Array[String] = []
	var rammed := false
	var outcome := ""

	for rnd in range(1, 13):
		# Who sets the range: the faster ship, with luck.
		var band := String(o["range"])
		if band != their_range:
			var ours := _speed(us["ship"]) * s.rng.randf_range(0.7, 1.3)
			var theirs := _speed(them["ship"]) * s.rng.randf_range(0.7, 1.3)
			band = band if ours >= theirs else their_range

		# Merchant tries to slip away at long range.
		if e["kind"] == "merchant" and band == "long" and s.rng.randf() < float(tr["caution"]) * 0.2 * _speed(them["ship"]) / max(0.1, _speed(us["ship"])):
			outcome = "escaped"
			lines.append("Round %d: she slips away in the smoke." % rnd)
			break

		# Ram
		if o["ram"] and not rammed and band == "close":
			rammed = true
			var ratio := sqrt(float(us["ship"]["hull_max"]) / float(them["ship"]["hull_max"]))
			them["ship"]["hull"] = float(them["ship"]["hull"]) - 25.0 * ratio
			us["ship"]["hull"] = float(us["ship"]["hull"]) - 18.0 / ratio
			us["ship"]["rig"] = max(10.0, float(us["ship"]["rig"]) - 10.0)
			lines.append("Round %d: you ram her! Both hulls stove in and locked together." % rnd)

		# Broadsides
		var mine := _broadside(s, us, them, band, String(o["shot"]), true)
		var theirs_b := _broadside(s, them, us, band, their_shot, false)
		lines.append("Round %d (%s): you %s; she %s." % [rnd, band, mine, theirs_b])

		if float(them["ship"]["hull"]) <= 0.0:
			outcome = "sunk_them"
			break
		if float(us["ship"]["hull"]) <= 0.0:
			outcome = "we_sank"
			break
		if int(us["crew"]) <= 0:
			outcome = "boarded_lost"
			break

		# Boarding
		var we_board: bool = o["board"] and band == "close" and (rnd >= 2 or rammed)
		var they_board: bool = e["kind"] == "pirate" and band == "close" and rnd >= 2
		if we_board or they_board:
			var att := us if we_board else them
			var dfn := them if we_board else us
			var bonus := 1.15 if rammed else 1.0
			var sa := float(att["crew"]) * (0.5 + float(att["morale"]) / 100.0) * bonus
			var sd := float(dfn["crew"]) * (0.5 + float(dfn["morale"]) / 100.0) * 1.2
			var win: bool = s.rng.randf() < sa / max(1.0, sa + sd)
			var loser := dfn if win else att
			var winner := att if win else dfn
			var l_loss := int(float(loser["crew"]) * s.rng.randf_range(0.4, 0.7))
			var w_loss := int(l_loss * s.rng.randf_range(0.2, 0.5))
			loser["crew"] = int(loser["crew"]) - l_loss
			winner["crew"] = max(1, int(winner["crew"]) - w_loss)
			var we_won: bool = (win and we_board) or (not win and not we_board)
			lines.append("Round %d: %s! %s" % [rnd, "You board her" if we_board else "They board you",
				"The deck is ours." if we_won else "Your men are beaten back."])
			if we_won:
				outcome = "prize"
			elif we_board and (e["kind"] != "pirate" or s.rng.randf() < 0.5):
				# Beaten back; the fight goes on, but you won't try again.
				us["morale"] = max(0.0, float(us["morale"]) - 20.0)
				o["board"] = false
				continue
			else:
				# They counter-board, or carried your deck.
				outcome = "boarded_lost"
			break

		# Strike colours?
		var their_hp := float(them["ship"]["hull"]) / float(them["ship"]["hull_max"])
		var strike_at := 0.2 + 0.25 * float(tr["caution"])
		if their_hp < strike_at or float(them["morale"]) < 15.0 or float(them["crew"]) < float(them["crew0"]) * 0.25:
			outcome = "prize"
			lines.append("Round %d: she strikes her colours!" % rnd)
			break
		if float(us["morale"]) < 10.0:
			outcome = "we_struck"
			lines.append("Round %d: your crew haul down the colours." % rnd)
			break

	if outcome == "":
		outcome = "stalemate"
		lines.append("Night falls; the ships draw apart.")

	s.crew = int(us["crew"])
	s.morale = clamp(float(us["morale"]), 0.0, 100.0)
	s.ship = us["ship"]
	return _after_combat(s, e, outcome, lines)

static func _broadside(s: GameState, a: Dictionary, d: Dictionary, band: String, shot: String, is_player: bool) -> String:
	var guns := int(a["ship"]["guns"])
	if is_player:
		var need := guns * 0.005
		if float(s.stores.get("powder", 0.0)) < need:
			return "have no powder"
		s.stores["powder"] = float(s.stores["powder"]) - need
	var manning: float = clamp(float(a["crew"]) / max(1.0, guns * 4.0), 0.2, 1.0)
	var acc := 0.75 if band == "close" else 0.35
	var hits := guns / 2.0 * acc * manning * s.rng.randf_range(0.7, 1.3)
	var hull := 0.0
	var rig := 0.0
	var kills := 0.0
	match shot:
		"round":
			hull = hits * 1.6
			kills = hits * 0.15
		"chain":
			rig = hits * 2.0
			hull = hits * 0.4
		"grape":
			kills = hits * (0.9 if band == "close" else 0.18)
			hull = hits * 0.2
	d["ship"]["hull"] = float(d["ship"]["hull"]) - hull
	d["ship"]["rig"] = max(5.0, float(d["ship"]["rig"]) - rig)
	var k := int(round(kills))
	d["crew"] = max(0, int(d["crew"]) - k)
	d["morale"] = max(0.0, float(d["morale"]) - (k * 100.0 / max(1.0, float(d["crew0"]))) * 0.5 - hull * 0.15)
	return "fire %s shot (hull -%d, rig -%d, %d killed)" % [shot, hull, rig, k]

static func _after_combat(s: GameState, e: Dictionary, outcome: String, lines: Array[String]) -> Dictionary:
	var text := ""
	match outcome:
		"prize":
			s.prizes_taken += 1
			s.chest += float(e["coin"])
			var took := ""
			for g in e["cargo"]:
				var t: float = min(float(e["cargo"][g]), s.cargo_free())
				if t > 0.0:
					s.cargo[g] = float(s.cargo.get(g, 0.0)) + t
					took += " %d t %s," % [t, World.GOODS[g]["name"].to_lower()]
			# Her stores come with her: pirates lived off their prizes.
			for st in [["food", float(e["crew"]) * FOOD_PER_MAN * 40.0], ["water", float(e["crew"]) * WATER_PER_MAN * 25.0],
					["powder", float(e["ship"]["guns"]) * 0.06]]:
				var amt: float = min(float(st[1]), s.cargo_free())
				if amt > 0.0:
					s.stores[st[0]] = float(s.stores.get(st[0], 0.0)) + amt
			var join := int(min(float(e["crew"]) * 0.2, float(int(s.ship["crew_cap"]) - s.crew)))
			join = max(0, join)
			s.crew += join
			text = "Prize taken! %d coin%s %d of her hands sign on." % [e["coin"], took.trim_suffix(",") + "." if took != "" else ".", join]
			_reputation_after(s, e, true)
			if s.role == "Pirate":
				s.morale = min(100.0, s.morale + 25.0)
				s.days_since_plunder = 0
		"sunk_them":
			s.ships_sunk += 1
			text = "She goes down by the head. No prize, but no witnesses."
			_reputation_after(s, e, false)
		"escaped":
			text = "She got away."
		"stalemate":
			text = "Neither side would yield; you part at nightfall."
		"we_struck", "boarded_lost":
			if e["kind"] == "navy" and s.role == "Pirate":
				return _with_lines(_end(s, "Taken by the %s navy. Hanged at low-water mark." % e["nation"]), lines)
			if s.crew <= 0:
				return _with_lines(_end(s, "Your crew are all dead and the %s is taken." % s.ship["label"]), lines)
			var took2 := s.chest * 0.6
			s.chest -= took2
			s.cargo = {}
			if e["kind"] == "pirate" and s.rng.randf() < 0.12:
				return _with_lines(_end(s, "The pirates took your ship and made you walk the plank."), lines)
			text = "Beaten. They take the hold and %d coin, and leave you your ship." % took2
		"we_sank":
			return _with_lines(_end(s, "The %s goes down under her guns. You are lost with her." % s.ship["label"]), lines)
	return {"text": text, "lines": lines, "outcome": outcome}

static func _with_lines(d: Dictionary, lines: Array[String]) -> Dictionary:
	d["lines"] = lines
	return d

static func _reputation_after(s: GameState, e: Dictionary, prize: bool) -> void:
	if e["kind"] == "pirate":
		for n in World.NATIONS:
			if n != "Denmark":
				s.reputation[n] = min(100, int(s.reputation[n]) + 3)
		return
	if s.role == "Pirate":
		var value := float(e["coin"]) + (500.0 if prize else 0.0)
		s.bounty += value * 0.3
		s.infamy += 5.0
		s.reputation[e["nation"]] = max(-100, int(s.reputation[e["nation"]]) - 10)
	else:
		s.reputation[e["nation"]] = max(-100, int(s.reputation[e["nation"]]) - 5)

# ------------------------------------------------------------------ retirement

static func net_worth(s: GameState) -> float:
	var cargo_val := 0.0
	for g in s.cargo:
		cargo_val += float(s.cargo[g]) * float(World.GOODS[g]["base"]) * 0.8
	return s.purse + s.chest + cargo_val + float(World.SHIPS[s.ship["cls"]]["price"]) * 0.5 * float(s.ship["hull"]) / float(s.ship["hull_max"])

static func retire(s: GameState) -> Dictionary:
	if s.at_sea():
		return {"text": "Retire ashore, not at sea."}
	var worth := s.purse + 0.5 * (net_worth(s) - s.purse)
	var tier := ""
	if worth > 50000:
		tier = "You buy a great estate and are made a baronet. Your portrait hangs in the hall."
	elif worth > 15000:
		tier = "You retire a gentleman of means, with a sugar plantation and a seat on the island council."
	elif worth > 4000:
		tier = "You keep a respectable tavern by the harbour and tell lies about the old days."
	else:
		tier = "You end your days poor, mending nets and cadging rum."
	if s.role == "Pirate" and s.bounty > 2000:
		tier += " The bounty on your head means you sleep with a pistol under the pillow."
	s.ended = true
	s.end_reason = "Retired aged %d with %d pieces of eight. %s" % [s.age, worth, tier]
	s.say(s.end_reason)
	return {"text": s.end_reason, "score": int(worth)}
