class_name Sim
extends RefCounted
## All the rules: careers, voyage days, events, markets, nations and
## reputation, encounters, and battles. Static functions over a GameState so
## the same code drives the UI and a headless test/sim run.

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
## Navy pay to your purse, pieces of eight a month.
const NAVY_PAY := {"Lieutenant": 30.0, "Commander": 50.0, "Captain": 80.0}
## Prize Act 1708: a captain's share of a condemned prize was 3/8.
const NAVY_PRIZE_SHARE := 0.375
const MARQUE_FEE := 600.0

# ------------------------------------------------------------------ setup

static func new_game(role: String, nation: String = "England", seed: int = 0, patron: String = "") -> GameState:
	var s := GameState.new()
	if seed == 0:
		s.rng.randomize()
	else:
		s.rng.seed = seed
	s.role = role
	s.nation = nation
	for n in World.NATIONS:
		s.reputation[n] = 0
	s.reputation[nation] = 20
	var label: String = World.START_SHIPS.get(role, World.START_SHIPS["Trader"])[nation]
	match role:
		"Pirate":
			s.ship = make_ship("sloop", label)
			s.crew = 50
			s.chest = 300.0
			s.morale = 60.0
			s.bounty = 200.0
			s.infamy = 10.0
			s.location = "st_thomas"
			s.stores = {"food": 3.0, "water": 5.0, "powder": 3.0, "spares": 2.0, "medicine": 0.1}
			for n in World.POWERS:
				s.reputation[n] = -20
			s.reputation[nation] = 0
		"Privateer":
			if patron == "":
				patron = _default_patron(nation, 0)
			s.patron = patron
			s.ship = make_ship("sloop", label)
			s.crew = 60
			s.chest = 400.0
			s.morale = 65.0
			s.location = World.HOME[patron]
			s.reputation[patron] = max(s.rep(patron), 25)
			s.stores = {"food": 3.0, "water": 5.0, "powder": 3.0, "spares": 2.0, "medicine": 0.2}
		"Navy":
			s.navy_rank = "Lieutenant"
			s.ship = make_ship("brigantine", label)
			s.owns_ship = false
			s.crew = 80
			s.chest = 0.0
			s.purse = 100.0
			s.morale = 70.0
			s.location = World.HOME[nation]
			s.reputation[nation] = 35
			s.stores = {"food": 4.0, "water": 6.0, "powder": 4.0, "spares": 3.0, "medicine": 0.3}
		_:
			s.role = "Trader"
			s.ship = make_ship("fluyt", label)
			s.crew = 18
			s.chest = 1500.0
			s.location = World.HOME[nation]
			s.stores = {"food": 2.0, "water": 3.0, "powder": 1.0, "spares": 2.0, "medicine": 0.2}
			var here := World.port_by_id(s.location)
			var g: String = here["produces"][0] if here["produces"].size() > 0 else "sugar"
			s.cargo = {g: 20.0}
	_init_markets(s)
	s.war_note = war_signature(s.day)
	s.last_pay_day = s.day
	var role_text := s.role
	if s.role == "Privateer":
		role_text = "%s privateer under a %s letter of marque" % [World.ADJ[nation], World.ADJ[s.patron]]
	elif s.role == "Navy":
		role_text = "%s of the %s navy" % [s.navy_rank, World.ADJ[nation]]
	else:
		role_text = "%s %s" % [World.ADJ[nation], s.role.to_lower()]
	s.say("%s, %s, takes command of the %s %s at %s." % [s.captain_name, role_text,
		s.ship["name"].to_lower(), s.ship["label"], World.port_by_id(s.location)["name"]])
	s.say(war_headline(s.day))
	return s

## A privateer needs a commission from a power at war. In 1675 France was
## at war with the Dutch and Spain, and English buccaneers sailed under French
## commissions — so default to your own nation if it's at war, else France.
static func _default_patron(nation: String, day: int) -> String:
	if World.enemies_of(nation, day).size() > 0:
		return nation
	for n in World.POWERS:
		if World.enemies_of(n, day).size() > 0:
			return n
	return nation

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

# ------------------------------------------------------------------ calendar & news

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

static func war_signature(day: int) -> String:
	var parts := []
	for i in World.POWERS.size():
		for j in range(i + 1, World.POWERS.size()):
			if World.at_war(World.POWERS[i], World.POWERS[j], day):
				parts.append("%s–%s" % [World.POWERS[i], World.POWERS[j]])
	return ", ".join(parts)

static func war_headline(day: int) -> String:
	var sig := war_signature(day)
	return "At war: %s." % sig if sig != "" else "The powers are at peace."

## One day passes anywhere: markets, news of war and peace, navy pay,
## letters of marque lapsing.
static func _day_passes(s: GameState) -> void:
	s.day += 1
	s.age += 1.0 / 365.0
	tick_markets(s)
	var sig := war_signature(s.day)
	if sig != s.war_note:
		s.war_note = sig
		s.say("News from Europe! " + war_headline(s.day))
	if s.role == "Navy":
		s.days_since_prize += 1
		if s.day - s.last_pay_day >= 30:
			s.last_pay_day = s.day
			s.purse += float(NAVY_PAY.get(s.navy_rank, 30.0))
		if s.days_since_prize > 150:
			s.days_since_prize = 60
			s.add_rep(s.nation, -8)
			s.say("A sharp letter from the Admiralty: no prizes, no pirates taken. Your standing suffers.")
	if s.role == "Privateer" and World.enemies_of(s.patron, s.day).is_empty():
		s.role = "Trader"
		s.say("Peace! Your %s letter of marque is void. Take a prize now and you'll hang as a pirate." % World.ADJ[s.patron])
		s.patron = ""

# ------------------------------------------------------------------ nations & ports

## "" if you may enter, else why not.
static func port_open(s: GameState, port_id: String) -> String:
	var p := World.port_by_id(port_id)
	if p["haven"]:
		return ""
	var n: String = p["nation"]
	var name: String = p["name"].split(",")[0]
	match s.role:
		"Pirate":
			if s.rep(n) >= 25:
				return ""
			return "The fort at %s fires on pirates (needs Friendly standing with %s)." % [name, World.ADJ[n]]
		_:
			if World.at_war(n, s.flag(), s.day):
				return "%s is an enemy port: %s is at war with %s." % [name, n, s.flag()]
			if s.rep(n) <= -25:
				return "The governor of %s has closed the port to you." % name
	return ""

static func at_own_port(s: GameState) -> bool:
	return not s.at_sea() and World.port_by_id(s.location)["nation"] == s.nation

static func port_nation(s: GameState) -> String:
	return "" if s.at_sea() else String(World.port_by_id(s.location)["nation"])

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
	if s.role == "Navy" and at_own_port(s) and store != "medicine":
		return 0.0   # the Victualling Board pays
	if s.role == "Pirate":
		p *= 1.3
	return p

static func buy_store(s: GameState, store: String, tons: float) -> String:
	if s.at_sea():
		return "You are at sea."
	tons = min(tons, s.cargo_free())
	var unit := store_price(s, store)
	if unit > 0.0:
		tons = min(tons, floor(s.chest / unit * 10.0) / 10.0)
	if tons <= 0.0:
		return "No room or no coin."
	s.chest -= unit * tons
	s.stores[store] = float(s.stores.get(store, 0.0)) + tons
	return "Took on %.1f t of %s%s." % [tons, World.STORES[store]["name"], " from the King's stores" if unit == 0.0 else ""]

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
	if s.role == "Pirate" and not port["haven"] and s.rep(port["nation"]) < 40:
		return "Only a pirate haven, or a governor who is very friendly, will let you recruit here."
	n = min(n, int(s.ship["crew_cap"]) - s.crew)
	var each := 6.0   # a month's advance
	if s.role in ["Pirate", "Privateer"]:
		each = 0.0    # no prey, no pay
	elif s.role == "Navy" and at_own_port(s):
		each = 0.0    # the press gang
	if each > 0.0:
		n = min(n, int(s.chest / each))
	if n <= 0:
		return "No room or no coin."
	s.chest -= each * n
	s.crew += n
	return "%s %d hands." % ["Pressed" if s.role == "Navy" else "Signed on", n]

static func pay_wages(s: GameState) -> String:
	var amt: float = min(s.pay_owed, s.chest)
	if amt <= 0.0:
		return "Nothing owed." if s.pay_owed <= 0.0 else "The chest is empty."
	s.chest -= amt
	s.pay_owed -= amt
	s.morale = min(100.0, s.morale + 15.0 * amt / max(1.0, amt + s.pay_owed))
	return "Paid %d in wages." % amt

static func repair_cost(s: GameState) -> float:
	var c := (float(s.ship["hull_max"]) - float(s.ship["hull"])) * 8.0 + (100.0 - float(s.ship["rig"])) * 6.0
	if s.role == "Navy" and at_own_port(s):
		return 0.0   # the King's dockyard
	return c

static func repair(s: GameState) -> String:
	if s.at_sea():
		return "You are at sea."
	var damaged: bool = float(s.ship["hull"]) < float(s.ship["hull_max"]) or float(s.ship["rig"]) < 100.0
	if not damaged:
		return "She's sound."
	var cost := repair_cost(s)
	if cost > s.chest:
		return "The shipwright wants %d; you haven't got it." % cost
	s.chest -= cost
	s.ship["hull"] = s.ship["hull_max"]
	s.ship["rig"] = 100.0
	return "Repaired%s." % (" in the King's dockyard" if cost == 0.0 else " for %d" % cost)

## Trader/Privateer/Navy: move money from the ship's chest to your own purse.
static func bank(s: GameState, amt: float) -> String:
	if s.at_sea():
		return "You are at sea."
	if s.role == "Pirate":
		return "Pirates share out; they don't bank."
	amt = min(amt, s.chest)
	s.chest -= amt
	s.purse += amt
	return "Banked %d." % amt

static func withdraw(s: GameState, amt: float) -> String:
	if s.at_sea():
		return "You are at sea."
	amt = min(amt, s.purse)
	if amt <= 0.0:
		return "Your purse is empty."
	s.purse -= amt
	s.chest += amt
	return "Drew %d from your purse." % amt

## Pirates and privateers sailed on shares: captain 2, each hand 1, after a
## common fund for the ship.
static func share_out(s: GameState) -> String:
	if s.at_sea():
		return "Plunder is shared out ashore."
	if s.role == "Pirate" and not World.port_by_id(s.location)["haven"]:
		return "Pirates share out in a haven, away from the governor's men."
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
		_day_passes(s)
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

# ------------------------------------------------------------------ the governor's office

## Role changes available here and now: [{id, label, ok, why}].
static func office_options(s: GameState) -> Array:
	var out := []
	if s.at_sea():
		return out
	var n := port_nation(s)
	var haven: bool = World.port_by_id(s.location)["haven"]
	if not haven:
		var why := ""
		if not (s.role in ["Trader", "Privateer"]):
			why = "Only a trader or privateer can buy a letter of marque."
		elif World.enemies_of(n, s.day).is_empty():
			why = "%s is at peace with everyone: no marque to be had." % n
		elif s.rep(n) < 0:
			why = "The governor doesn't trust you (needs Neutral or better)."
		elif s.role == "Privateer" and s.patron == n:
			why = "You already sail under a %s marque." % World.ADJ[n]
		out.append({"id": "marque", "label": "Buy a %s letter of marque (%d) — legal prizes: %s" % [World.ADJ[n],
			marque_fee(s, n), ", ".join(World.enemies_of(n, s.day))], "ok": why == "", "why": why})
		if s.role == "Pirate":
			var free := World.pardon_on_offer(n, s.day)
			out.append({"id": "pardon", "label": "Take the King's pardon (free, by royal proclamation)" if free else
				"Buy a pardon from the governor (%d)" % pardon_cost(s, n), "ok": free or s.chest + s.purse >= pardon_cost(s, n),
				"why": "" if free or s.chest + s.purse >= pardon_cost(s, n) else "Not enough coin for the bribe."})
		if s.role in ["Trader", "Privateer"] and n == s.nation:
			var w := ""
			if s.rep(n) < 60:
				w = "Needs Honoured standing (60) with %s." % n
			elif s.prizes_taken + s.pirates_taken < 3:
				w = "Needs a fighting record: 3 prizes or pirates taken."
			out.append({"id": "commission", "label": "Offer your services to the %s navy" % World.ADJ[n], "ok": w == "", "why": w})
		if s.role == "Navy" and n == s.nation:
			var w2 := ""
			if s.rep(n) < 30:
				w2 = "The Admiralty won't release an officer in disgrace (needs standing 30)."
			elif s.purse + s.chest < float(World.SHIPS["sloop"]["price"]):
				w2 = "You'd be beached: save %d for a sloop of your own first." % World.SHIPS["sloop"]["price"]
			out.append({"id": "resign", "label": "Resign your commission and buy a sloop", "ok": w2 == "", "why": w2})
	return out

static func marque_fee(s: GameState, n: String) -> float:
	return MARQUE_FEE * (0.5 if s.rep(n) >= 25 else 1.0)

static func pardon_cost(s: GameState, n: String) -> float:
	return 500.0 + s.bounty * 0.5

static func _spend(s: GameState, amt: float) -> bool:
	if s.chest + s.purse < amt:
		return false
	var from_chest: float = min(s.chest, amt)
	s.chest -= from_chest
	s.purse -= amt - from_chest
	return true

static func office(s: GameState, id: String) -> String:
	for o in office_options(s):
		if o["id"] == id and not o["ok"]:
			return o["why"]
	var n := port_nation(s)
	match id:
		"marque":
			if not _spend(s, marque_fee(s, n)):
				return "Not enough coin for the fee."
			if s.role == "Trader" and s.pay_owed > 0.0:
				pay_wages(s)
			s.role = "Privateer"
			s.patron = n
			s.pay_owed = 0.0
			s.morale = min(100.0, s.morale + 10.0)
			return "Letter of marque from the governor of %s. You may take %s ships as lawful prize. The crew sign new articles: no prey, no pay." % [
				World.port_by_id(s.location)["name"].split(",")[0], " and ".join(World.enemies_of(n, s.day))]
		"pardon":
			if not World.pardon_on_offer(n, s.day) and not _spend(s, pardon_cost(s, n)):
				return "Not enough coin."
			s.role = "Trader"
			s.nation = n
			s.bounty = 0.0
			s.infamy *= 0.5
			s.reputation[n] = max(s.rep(n), 10) + 5
			for m in World.POWERS:
				if m != n:
					s.add_rep(m, 5)
			return "Pardoned. You swear allegiance to the %s crown and become an honest %s trader — for now." % [World.ADJ[n], World.ADJ[n]]
		"commission":
			var value := float(World.SHIPS[s.ship["cls"]]["price"]) * 0.5
			s.purse += value
			s.owns_ship = false
			s.role = "Navy"
			s.navy_rank = "Commander"
			s.patron = ""
			s.pay_owed = 0.0
			s.days_since_prize = 0
			s.last_pay_day = s.day
			return "Commissioned Commander in the %s navy. The Crown buys your ship into the service for %d." % [World.ADJ[n], value]
		"resign":
			var price := float(World.SHIPS["sloop"]["price"])
			_spend(s, price)
			var old: Dictionary = s.ship
			s.ship = make_ship("sloop", old["label"].trim_prefix("HMS "))
			s.owns_ship = true
			s.crew = min(s.crew, int(s.ship["crew_cap"]))
			_trim_hold(s)
			s.role = "Trader"
			s.navy_rank = ""
			return "You resign your commission, hand back the %s and buy a sloop of your own." % old["label"]
	return "?"

## Turn pirate: run up the black flag, here at sea.
static func turn_pirate(s: GameState) -> String:
	if s.role == "Pirate":
		return "You already are one."
	if not s.at_sea():
		return "Put to sea first — not under the guns of the fort."
	var old := s.role
	var stay_loyal := 0
	if old == "Navy":
		stay_loyal = int(s.crew * clamp(s.morale / 150.0, 0.1, 0.7))
		s.crew -= stay_loyal
		s.add_rep(s.nation, -60)
		s.bounty += 2000.0
		s.owns_ship = true
	else:
		s.add_rep(s.nation, -40)
		s.bounty += 1000.0
		s.morale = min(100.0, s.morale + 10.0)
	for n in World.POWERS:
		if n != s.nation:
			s.add_rep(n, -10)
	s.infamy += 15.0
	s.role = "Pirate"
	s.patron = ""
	s.navy_rank = ""
	s.pay_owed = 0.0
	var msg := "The black flag goes up. You are a pirate now."
	if stay_loyal > 0:
		msg += " %d men loyal to the King take to the boats." % stay_loyal
	return msg

# ------------------------------------------------------------------ shipyard

static func ship_offers(s: GameState) -> Array:
	var out := []
	if s.at_sea() or s.role == "Navy":
		return out
	var n := port_nation(s)
	for cls in World.SHIPS:
		if cls == s.ship["cls"]:
			continue
		var price := float(World.SHIPS[cls]["price"])
		var why := ""
		if cls == "frigate" and (s.role == "Pirate" or s.rep(n) < 60):
			why = "Frigates aren't sold to just anyone (needs Honoured standing)."
		var cost := price - trade_in(s)
		if why == "" and cost > s.chest + s.purse:
			why = "Costs %d after trade-in." % cost
		out.append({"cls": cls, "price": price, "cost": cost, "ok": why == "", "why": why})
	return out

static func trade_in(s: GameState) -> float:
	if not s.owns_ship:
		return 0.0
	return float(World.SHIPS[s.ship["cls"]]["price"]) * 0.5 * float(s.ship["hull"]) / float(s.ship["hull_max"])

static func buy_ship(s: GameState, cls: String) -> String:
	for o in ship_offers(s):
		if o["cls"] == cls:
			if not o["ok"]:
				return o["why"]
			_spend(s, float(o["cost"]))
			var old: Dictionary = s.ship
			s.ship = make_ship(cls, old["label"])
			s.owns_ship = true
			var gone: int = max(0, s.crew - int(s.ship["crew_cap"]))
			s.crew -= gone
			var sold := _trim_hold(s)
			return "Bought a %s; the %s goes to the yard.%s%s" % [s.ship["name"].to_lower(), old["name"].to_lower(),
				(" %d hands paid off." % gone) if gone > 0 else "", (" Sold %d t that wouldn't fit." % sold) if sold > 0.0 else ""]
	return "The yard has none."

## Drop cargo that doesn't fit the hold, at local prices. Returns tons sold.
static func _trim_hold(s: GameState) -> float:
	var sold := 0.0
	while s.cargo_free() < 0.0 and not s.cargo.is_empty():
		var g: String = s.cargo.keys()[0]
		var t: float = min(float(s.cargo[g]), -s.cargo_free())
		sell_good(s, g, t)
		sold += t
	while s.cargo_free() < 0.0:
		for st in s.stores:
			s.stores[st] = float(s.stores[st]) * 0.9
	return sold

# ------------------------------------------------------------------ voyage

static func can_sail_to(s: GameState, port_id: String) -> String:
	var p := World.port_by_id(port_id)
	if p.is_empty():
		return "No such port."
	if port_id == s.location:
		return "You're already there. (Use Cruise to hunt the sea lanes and come back.)"
	var why := port_open(s, port_id)
	if why != "":
		return why
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

## Cruise the lanes for some days and return to this port.
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
	_day_passes(s)
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
	match s.role:
		"Trader":
			s.pay_owed += s.crew * WAGE_PER_MAN_DAY
			if s.pay_owed > s.crew * 7.0:
				dm -= 0.5
		"Pirate", "Privateer":
			if s.days_since_plunder > 30:
				dm -= 0.4
		"Navy":
			if s.morale < 40.0:
				dm += 0.3   # the Articles of War, and the cat

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
	var mutiny_p := 0.03 if s.role == "Navy" else 0.08
	if s.morale < 15.0 and s.rng.randf() < mutiny_p:
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
	elif roll < storm_p + 0.055 + (0.07 if s.role in ["Pirate", "Privateer", "Navy"] else 0.06):
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
	var why := port_open(s, to)
	if why != "":
		# The world changed while you were at sea (war, or your name).
		s.voyage = {"from": to, "to": "st_thomas", "total_nm": World.distance_nm(p, World.port_by_id("st_thomas")), "done_nm": 0.0}
		s.say(why + " You bear away for St Thomas.")
		return {"type": "turned_away", "text": why}
	s.location = to
	s.voyage = {}
	s.days_since_fresh = 0
	s.health = min(100.0, s.health + 5.0)
	var text := "Dropped anchor at %s." % p["name"]
	if s.morale < 40.0 and s.role != "Navy":
		var gone := int(s.crew * (40.0 - s.morale) / 200.0)
		if gone > 0:
			s.crew -= gone
			text += " %d deserted ashore." % gone
	if s.role == "Trader" and s.pay_owed > 0.0 and s.chest > 0.0:
		text += " " + pay_wages(s)
	if s.role == "Navy" and at_own_port(s):
		text += _promotion(s)
	s.say(text)
	return {"type": "landfall", "text": text}

static func _promotion(s: GameState) -> String:
	var taken := s.prizes_taken + s.pirates_taken
	if s.navy_rank == "Lieutenant" and s.rep(s.nation) >= 45 and taken >= 2:
		s.navy_rank = "Commander"
		return " The Admiralty promotes you Commander."
	if s.navy_rank == "Commander" and s.rep(s.nation) >= 70 and taken >= 5:
		s.navy_rank = "Captain"
		var label: String = s.ship["label"]
		s.ship = make_ship("frigate", label)
		s.crew = min(int(s.ship["crew_cap"]), s.crew + 60)
		return " Made post Captain, and given a frigate: the %s." % label
	return ""

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

static func _pick_pirate_nation(s: GameState) -> String:
	# Buccaneers and Golden Age pirates were mostly English-speaking, then French.
	var r := s.rng.randf()
	if r < 0.45:
		return "England"
	if r < 0.75:
		return "France"
	if r < 0.9:
		return "Dutch"
	return "Spain"

static func make_encounter(s: GameState) -> Dictionary:
	var nation := _nearest_nation(s)
	if nation == "Denmark" or s.voyage.get("cruise", false) or s.rng.randf() < 0.45:
		nation = World.POWERS[s.rng.randi_range(0, 3)]
	var roll := s.rng.randf()
	# Navies were thin in the West Indies; most sails were merchants.
	var kind := "merchant"
	if roll < 0.60:
		kind = "merchant"
	elif roll < 0.72:
		kind = "navy"
	elif roll < 0.80:
		kind = "privateer" if not World.enemies_of(nation, s.day).is_empty() else "merchant"
	else:
		kind = "pirate"
	var cls := ""
	var pers := ""
	match kind:
		"merchant":
			cls = "fluyt" if s.rng.randf() < 0.6 else "merchantman"
			pers = "Cautious merchant" if s.rng.randf() < 0.6 else "Stubborn merchant"
		"navy":
			cls = "frigate" if s.rng.randf() < 0.3 else "brigantine"
			pers = "Dutiful navy"
		"privateer":
			cls = "sloop" if s.rng.randf() < 0.6 else "brigantine"
			pers = "Bold privateer"
		_:
			cls = "sloop" if s.rng.randf() < 0.65 else "brigantine"
			pers = "Greedy pirate" if s.rng.randf() < 0.55 else "Bloodthirsty pirate"
			nation = _pick_pirate_nation(s)
	var ship := make_ship(cls, "")
	var crew_frac: float = {"merchant": 0.7, "navy": 0.9, "privateer": 0.85, "pirate": 0.85}[kind]
	var crew := int(int(ship["crew_cap"]) * crew_frac * s.rng.randf_range(0.8, 1.1))
	var traits: Dictionary = World.PERSONALITIES[pers]
	var morale: float = {"merchant": 45.0, "navy": 75.0, "privateer": 65.0, "pirate": 55.0 + 30.0 * float(traits["aggression"])}[kind]
	var cargo := {}
	var coin := 0.0
	match kind:
		"merchant":
			var goods := World.GOODS.keys()
			var left: float = float(ship["cargo"]) * s.rng.randf_range(0.4, 0.8)
			for i in 3:
				var g: String = goods[s.rng.randi_range(0, goods.size() - 1)]
				var t: float = left / (3 - i) if g != "silver" else min(left / (3 - i), 4.0)
				cargo[g] = float(cargo.get(g, 0.0)) + t
				left -= t
			coin = s.rng.randf_range(200.0, 1500.0)
		"navy":
			coin = s.rng.randf_range(100.0, 400.0)
		"privateer":
			coin = s.rng.randf_range(200.0, 1200.0)
		_:
			coin = s.rng.randf_range(500.0, 3000.0)
			if s.rng.randf() < 0.3:
				cargo["silver"] = s.rng.randf_range(1.0, 3.0)
	var e := {"kind": kind, "nation": nation, "ship": ship, "crew": crew, "morale": morale,
		"personality": pers, "traits": traits, "cargo": cargo, "coin": coin}
	e["hostile"] = npc_hostile(s, e)
	e["text"] = encounter_text(s, e)
	return e

## Would this ship come for you? Navies hunt their enemies and anyone they
## have cause to hang; privateers hunt their patron's enemies; pirates hunt
## whoever they think they can take — but not their own brethren.
static func npc_hostile(s: GameState, e: Dictionary) -> bool:
	var tr: Dictionary = e["traits"]
	var n: String = e["nation"]
	var ours := power(s.ship, s.crew, s.morale)
	var theirs := power(e["ship"], int(e["crew"]), float(e["morale"]))
	match e["kind"]:
		"navy":
			var cause: bool = World.at_war(n, s.flag(), s.day) or s.rep(n) <= -25 \
				or (s.role == "Pirate" and s.rep(n) < 25)
			return cause and s.rng.randf() < float(tr["aggression"]) + 0.2
		"privateer":
			var cause2: bool = s.flag() != "" and World.at_war(n, s.flag(), s.day)
			return cause2 and s.rng.randf() < float(tr["aggression"]) and theirs / max(1.0, ours) > float(tr["caution"])
		"pirate":
			if s.role == "Pirate" and n == s.nation and e["personality"] != "Bloodthirsty pirate":
				return false   # brethren of the coast
			# Pirates hunted fat merchants; a ship full of fighting men was
			# poor pickings unless they badly outmatched her.
			var armed: bool = s.role != "Trader"
			var need: float = float(tr["caution"]) * (2.5 if armed else 1.2)
			return s.rng.randf() < float(tr["aggression"]) and theirs / max(1.0, ours) > need
	return false

static func describe(e: Dictionary) -> String:
	var adj: String = World.ADJ.get(e["nation"], "")
	var cls: String = e["ship"]["name"].to_lower()
	match e["kind"]:
		"navy":
			return "%s navy %s" % [adj, cls]
		"privateer":
			return "%s privateer %s" % [adj, cls]
		"pirate":
			return "pirate %s (%s crew)" % [cls, adj]
	return "%s %s" % [adj, cls]

static func encounter_text(s: GameState, e: Dictionary) -> String:
	var who := describe(e)
	var art := "an" if who.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
	var text := "Sail ho! %s %s, %d guns, ~%d men (%s)." % [art.capitalize(), who, e["ship"]["guns"], e["crew"], e["personality"]]
	if e["hostile"]:
		text += " She's bearing down on us!"
	elif e["kind"] == "pirate" and s.role == "Pirate" and e["nation"] == s.nation:
		text += " She dips her black flag: brethren of the coast."
	elif e["kind"] == "merchant":
		text += " A fat merchant."
	else:
		text += " She keeps her distance."
	return text

# ------------------------------------------------------------------ law & reputation

## Is taking this ship lawful prize for you?
static func attack_legal(s: GameState, e: Dictionary) -> bool:
	if e["kind"] == "pirate":
		return true
	var n: String = e["nation"]
	match s.role:
		"Pirate":
			return false
		"Privateer":
			return World.at_war(s.patron, n, s.day)
		_:
			return World.at_war(s.nation, n, s.day)

## Who thinks what of you if you attack her. result: prize | sunk | attempt.
## Hitting a nation's enemies pleases it and its allies; hitting a nation
## angers it and its allies; piracy makes everyone a little warier.
static func attack_effects(s: GameState, e: Dictionary, result: String) -> Dictionary:
	var scale: float = {"prize": 1.0, "sunk": 1.3, "attempt": 0.5}[result]
	var deltas := {}
	var t: String = e["nation"]
	if e["kind"] == "pirate":
		for n in World.POWERS:
			deltas[n] = int(round(3 * scale))
		return {"legal": true, "deltas": deltas, "becomes_pirate": false,
			"note": "Pirates are fair game: every crown is glad to see them taken."}
	var legal := attack_legal(s, e)
	var note := ""
	deltas[t] = -int(round(15 * scale))
	if s.rep(t) >= 25:
		deltas[t] -= int(round(15 * scale))
		note = "Betrayal: %s thought you a friend. " % t
	for n in World.POWERS:
		if n == t:
			continue
		var d := 0
		if World.at_war(n, t, s.day):
			d += int(round((8 if legal else 4) * scale))
		elif World.allied(n, t, s.day):
			d -= int(round(5 * scale))
		elif not legal:
			d -= int(round(3 * scale))
		if not legal and n == s.nation and s.role != "Pirate":
			d -= 10
		if legal and s.role == "Navy" and n == s.nation:
			d += 3
		deltas[n] = d
	if legal:
		note += "Lawful prize: %s is at war with %s." % [s.flag(), t]
	elif s.role == "Pirate":
		note += "Piracy, as ever."
	else:
		note += "PIRACY: %s is at peace with %s. You'd be a pirate from that moment." % [s.flag(), t]
	return {"legal": legal, "deltas": deltas, "becomes_pirate": not legal and s.role != "Pirate", "note": note}

static func effects_text(fx: Dictionary) -> String:
	var parts := []
	for n in World.POWERS:
		var d: int = fx["deltas"].get(n, 0)
		if d != 0:
			parts.append("%s %s%d" % [n, "+" if d > 0 else "−", absi(d)])
	return fx["note"] + ("  Standing: " + ", ".join(parts) if parts.size() > 0 else "")

static func _apply_effects(s: GameState, e: Dictionary, result: String) -> String:
	var fx := attack_effects(s, e, result)
	for n in fx["deltas"]:
		s.add_rep(n, int(fx["deltas"][n]))
	var out := ""
	if fx["becomes_pirate"]:
		var was := s.role
		s.role = "Pirate"
		s.patron = ""
		s.pay_owed = 0.0
		s.bounty += 500.0
		s.infamy += 10.0
		if was == "Navy":
			s.owns_ship = true
			s.navy_rank = ""
			s.bounty += 1500.0
		out = " You fired on a ship of a nation at peace: you are a pirate now."
	elif s.role == "Pirate" and e["kind"] != "pirate":
		s.bounty += (float(e["coin"]) + 500.0) * 0.3
		s.infamy += 5.0
	return out

# ------------------------------------------------------------------ battles

## Start a fight. action: attack | flee | sail_on. Returns null if no fight.
static func start_battle(s: GameState, action: String, orders: Dictionary = {}) -> Battle:
	var e: Dictionary = s.encounter
	if e.is_empty():
		return null
	if action != "attack" and not e["hostile"]:
		return null
	var o := {"range": "close", "shot": "round", "board": true, "ram": false}
	o.merge(orders, true)
	var mode := "flee"
	if action == "attack":
		mode = "ram" if o["ram"] else ("board" if o["board"] else "engage")
	o["mode"] = mode
	var p := {"ship": s.ship, "crew": s.crew, "morale": s.morale, "kind": s.role, "orders": o,
		"traits": {"caution": 0.4}, "powder": float(s.stores.get("powder", 0.0)),
		"nation": s.flag(), "pirate": s.role == "Pirate", "label": s.ship["label"]}
	var en := {"ship": e["ship"], "crew": int(e["crew"]), "morale": float(e["morale"]), "kind": e["kind"],
		"orders": enemy_orders(s, e, action), "traits": e["traits"], "nation": e["nation"],
		"pirate": e["kind"] == "pirate", "label": describe(e)}
	var b := Battle.new()
	b.setup(p, en, s.rng)
	b.set_meta("attacked", action == "attack")
	b.say("Wind steady. %s: %s." % [describe(e).capitalize(), "she runs" if en["orders"]["mode"] == "flee" else "she comes on"])
	return b

static func enemy_orders(s: GameState, e: Dictionary, action: String) -> Dictionary:
	var ours := power(s.ship, s.crew, s.morale)
	var theirs := power(e["ship"], int(e["crew"]), float(e["morale"]))
	var tr: Dictionary = e["traits"]
	var crew_edge: float = float(e["crew"]) / max(1.0, float(s.crew))
	match e["kind"]:
		"merchant":
			return {"mode": "flee", "range": "long", "shot": "chain", "board": false}
		"navy":
			return {"mode": "board" if crew_edge > 1.6 else "engage", "range": "close" if theirs >= ours * 0.8 else "long",
				"shot": "round", "board": crew_edge > 1.6}
		"privateer":
			if theirs < ours * float(tr["caution"]) * 1.5:
				return {"mode": "flee", "range": "long", "shot": "chain", "board": false}
			return {"mode": "board" if crew_edge > 1.2 else "engage", "range": "close", "shot": "grape", "board": crew_edge > 1.2}
		_:
			if action == "attack" and theirs < ours * float(tr["caution"]) * 1.3:
				return {"mode": "flee", "range": "long", "shot": "chain", "board": false}
			return {"mode": "board", "range": "close", "shot": "grape", "board": true}

## Apply a finished (or abandoned) battle to the career.
static func finish_battle(s: GameState, b: Battle) -> Dictionary:
	var e: Dictionary = s.encounter
	var pl: Dictionary = b.player()
	s.crew = int(pl["crew"])
	# The terror of the fight passes; what's left is how it went.
	var before := s.morale
	s.morale = clamp(lerpf(float(pl["morale"]), before, 0.6), 0.0, 100.0)
	if b.outcome in ["we_struck", "boarded_lost"]:
		s.morale = max(20.0, s.morale - 15.0)
	s.stores["powder"] = maxf(0.0, float(pl.get("powder", 0.0)))
	s.encounter = {}
	var outcome: String = b.outcome if b.outcome != "" else "stalemate"
	var lines: Array[String] = b.lines
	var attacked: bool = b.get_meta("attacked", false)
	var text := ""
	match outcome:
		"prize":
			text = _take_prize(s, e)
		"sunk_them":
			s.ships_sunk += 1
			if e["kind"] == "pirate":
				s.pirates_taken += 1
				s.days_since_prize = 0
			text = "She goes down by the head." + _apply_effects(s, e, "sunk") + _reward(s, e, false)
		"escaped":
			text = "She got away, hull-down to leeward."
			if attacked:
				text += _apply_effects(s, e, "attempt")
		"we_escaped":
			text = "You show her your heels and get clean away."
		"stalemate":
			text = "Night falls and you lose each other in the dark."
			if attacked:
				text += _apply_effects(s, e, "attempt")
		"we_struck", "boarded_lost":
			if e["kind"] == "navy" and s.role == "Pirate":
				return _with_lines(_end(s, "Taken by the %s navy. Tried at the Admiralty court and hanged at low-water mark." % World.ADJ.get(e["nation"], "")), lines)
			if s.crew <= 0:
				return _with_lines(_end(s, "Your crew are all dead and the %s is taken." % s.ship["label"]), lines)
			if e["kind"] == "pirate" and s.rng.randf() < 0.12:
				return _with_lines(_end(s, "The pirates took your ship and made you walk the plank."), lines)
			if e["kind"] in ["navy", "privateer"] and s.role != "Pirate":
				# A lawful enemy: prisoners are exchanged, the ship is lost.
				if s.owns_ship:
					var old: String = s.ship["label"]
					s.ship = make_ship("sloop", old)
					s.chest *= 0.3
					s.cargo = {}
					text = "Taken as a prize of war. You're exchanged weeks later and scrape together a sloop."
				else:
					s.add_rep(s.nation, -15)
					text = "You strike to the enemy. The court martial clears you, barely; the Admiralty gives you another ship."
					s.ship["hull"] = s.ship["hull_max"]
					s.ship["rig"] = 100.0
				if attacked:
					text += _apply_effects(s, e, "attempt")
			else:
				var took := s.chest * 0.6
				s.chest -= took
				s.cargo = {}
				text = "Beaten. They take the hold and %d coin, and leave you your ship." % took
		"we_sank":
			return _with_lines(_end(s, "The %s goes down under her guns. You are lost with her." % s.ship["label"]), lines)
	s.say(text)
	return {"text": text, "lines": lines, "outcome": outcome}

static func _take_prize(s: GameState, e: Dictionary) -> String:
	var legal := attack_legal(s, e)
	var coin: float = float(e["coin"])
	var cargo_value := 0.0
	var took := ""
	if s.role == "Navy" and legal:
		# Condemned in the prize court; the captain's share comes to you.
		for g in e["cargo"]:
			cargo_value += float(e["cargo"][g]) * float(World.GOODS[g]["base"]) * 0.8
		var share := (coin + cargo_value) * NAVY_PRIZE_SHARE
		s.purse += share
		took = " Your share of the prize court's award: %d." % share
	else:
		if s.role == "Privateer" and legal:
			coin *= 0.9   # the Crown's tenth
		s.chest += coin
		for g in e["cargo"]:
			var t: float = min(float(e["cargo"][g]), s.cargo_free())
			if t > 0.0:
				s.cargo[g] = float(s.cargo.get(g, 0.0)) + t
				took += " %d t %s," % [t, World.GOODS[g]["name"].to_lower()]
		took = (" Coin %d;%s" % [coin, took.trim_suffix(",")]) if took != "" else " Coin %d." % coin
	# Her stores come with her: crews lived off their prizes.
	for st in [["food", float(e["crew"]) * FOOD_PER_MAN * 40.0], ["water", float(e["crew"]) * WATER_PER_MAN * 25.0],
			["powder", float(e["ship"]["guns"]) * 0.06]]:
		var amt: float = min(float(st[1]), s.cargo_free())
		if amt > 0.0:
			s.stores[st[0]] = float(s.stores.get(st[0], 0.0)) + amt
	var join := 0
	if s.role != "Navy":
		join = max(0, int(min(float(e["crew"]) * 0.2, float(int(s.ship["crew_cap"]) - s.crew))))
		s.crew += join
	s.prizes_taken += 1 if e["kind"] != "pirate" else 0
	if e["kind"] == "pirate":
		s.pirates_taken += 1
	s.days_since_prize = 0
	if s.role in ["Pirate", "Privateer"]:
		s.morale = min(100.0, s.morale + 25.0)
		s.days_since_plunder = 0
	var text := "Prize taken!%s%s" % [took, (" %d of her hands sign on." % join) if join > 0 else ""]
	text += _apply_effects(s, e, "prize")
	text += _reward(s, e, true)
	return text

## Governors paid for pirates brought in, dead or alive.
static func _reward(s: GameState, e: Dictionary, alive: bool) -> String:
	if e["kind"] != "pirate" or s.role == "Pirate":
		return ""
	var r := 300.0 + float(e["crew"]) * (15.0 if alive else 5.0)
	s.purse += r
	return " Reward for the pirates: %d." % r

## Headless: start, run to the end, apply.
static func resolve(s: GameState, action: String, orders: Dictionary = {}) -> Dictionary:
	var e: Dictionary = s.encounter
	if e.is_empty():
		return {"text": "Nothing in sight."}
	var res := {}
	match action:
		"trade":
			if e["hostile"] or e["kind"] != "merchant":
				res = {"text": "She won't heave to for you."}
			else:
				res = _trade_at_sea(s, e)
			s.encounter = {}
		"surrender":
			res = _surrender(s, e)
			s.encounter = {}
		_:
			var b := start_battle(s, action, orders)
			if b == null:
				s.encounter = {}
				res = {"text": "She passes astern. You hold your course." if action == "sail_on" else "You crowd on sail and leave her behind."}
			else:
				b.run()
				return finish_battle(s, b)
	if res.has("text") and not s.ended:
		s.say(res["text"])
	return res

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

static func _surrender(s: GameState, e: Dictionary) -> Dictionary:
	if not e["hostile"]:
		return {"text": "She has no quarrel with you."}
	if e["kind"] == "navy" and s.role == "Pirate":
		return _end(s, "Taken by the %s navy. Tried at the Admiralty court and hanged at low-water mark." % World.ADJ.get(e["nation"], ""))
	var took := s.chest * 0.5
	s.chest -= took
	s.cargo = {}
	s.morale = max(0.0, s.morale - 25.0)
	return {"text": "You strike your colours. They strip the hold and take %d from the chest, then let you go." % took}

static func _with_lines(d: Dictionary, lines: Array[String]) -> Dictionary:
	d["lines"] = lines
	return d

# ------------------------------------------------------------------ retirement

static func net_worth(s: GameState) -> float:
	var cargo_val := 0.0
	for g in s.cargo:
		cargo_val += float(s.cargo[g]) * float(World.GOODS[g]["base"]) * 0.8
	var ship_val := trade_in(s)
	return s.purse + s.chest + cargo_val + ship_val

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
	if s.role == "Navy":
		tier += " The Admiralty grants you half-pay as a %s." % s.navy_rank
	if s.role == "Pirate" and s.bounty > 2000:
		tier += " The bounty on your head means you sleep with a pistol under the pillow."
	s.ended = true
	s.end_reason = "Retired aged %d with %d pieces of eight. %s" % [s.age, worth, tier]
	s.say(s.end_reason)
	return {"text": s.end_reason, "score": int(worth)}
