extends SceneTree
## Headless checks + an all-AI career sweep per role.
## Run: godot --headless --path . -s tests/run_tests.gd

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", what)

func _init() -> void:
	_test_markets()
	_test_nations()
	_test_reputation()
	_test_voyage()
	_test_roles()
	_test_battles()
	_test_basket()
	_test_passage()
	_sweep()
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)

func _test_markets() -> void:
	var s := Sim.new_game("Trader", "England", 1)
	var before := s.chest
	var p := Sim.buy_price(s, s.location, "cloth")
	Sim.buy_good(s, "cloth", 5.0)
	check(s.chest < before, "buying cloth costs coin")
	check(Sim.buy_price(s, s.location, "cloth") > p, "buying raises the price")
	check(Sim.sell_price(s, "bridgetown", "sugar") < Sim.sell_price(s, "oranjestad", "sugar"), "sugar dearer where wanted")
	var d := World.distance_nm(World.port_by_id("bridgetown"), World.port_by_id("willemstad"))
	check(d > 500.0 and d < 600.0, "Bridgetown–Willemstad ~550 nm (got %d)" % d)

## The recorded wars drive friend and foe.
func _test_nations() -> void:
	var d1675 := 0
	check(World.at_war("France", "Dutch", d1675), "1675: France at war with the Dutch")
	check(World.at_war("France", "Spain", d1675), "1675: France at war with Spain")
	check(not World.at_war("England", "France", d1675), "1675: England at peace with France")
	check(World.allied("Dutch", "Spain", d1675), "1675: Dutch and Spain allied against France")
	var d1690 := int((1690.0 - World.START_YEAR) * 365)
	check(World.at_war("England", "France", d1690), "1690: Nine Years' War")
	check(World.allied("England", "Dutch", d1690), "1690: England and the Dutch allies")
	var d1705 := int((1705.0 - World.START_YEAR) * 365)
	check(World.at_war("England", "Spain", d1705) and World.allied("France", "Spain", d1705), "1705: Spanish Succession lines")
	var d1700 := int((1700.0 - World.START_YEAR) * 365)
	check(Sim.war_signature(d1700) == "", "1700: general peace")
	check(World.pardon_on_offer("England", int((1718.0 - World.START_YEAR) * 365)), "1718: Act of Grace on offer")

## His ask: in good standing with England, hitting the French helps; hitting
## the English hurts.
func _test_reputation() -> void:
	var s := Sim.new_game("Privateer", "England", 5, "England")
	s.day = int((1690.0 - World.START_YEAR) * 365)   # England at war with France
	s.reputation["England"] = 40
	var fr := {"kind": "merchant", "nation": "France", "coin": 500.0, "crew": 15, "ship": Sim.make_ship("fluyt", ""), "cargo": {}}
	var en := {"kind": "merchant", "nation": "England", "coin": 500.0, "crew": 15, "ship": Sim.make_ship("fluyt", ""), "cargo": {}}
	var fx_fr := Sim.attack_effects(s, fr, "prize")
	var fx_en := Sim.attack_effects(s, en, "prize")
	check(fx_fr["legal"] and fx_fr["deltas"]["England"] > 0 and fx_fr["deltas"]["Dutch"] > 0 and fx_fr["deltas"]["France"] < 0,
		"French prize: England and the Dutch (allies at war with France) pleased, France angered")
	check(not fx_en["legal"] and fx_en["becomes_pirate"] and fx_en["deltas"]["England"] <= -30,
		"English prize as an English privateer: piracy and betrayal")
	var p := Sim.new_game("Pirate", "England", 6)
	p.day = s.day
	var fx_p := Sim.attack_effects(p, fr, "prize")
	check(fx_p["deltas"]["England"] > 0, "a pirate preying on the French still pleases England at war with France")
	# Port access follows standing.
	p.reputation["England"] = 30
	check(Sim.port_open(p, "bridgetown") == "", "a Friendly pirate may enter an English port")
	p.reputation["England"] = 0
	check(Sim.port_open(p, "bridgetown") != "", "otherwise the fort fires")
	check(Sim.port_open(s, "saint_pierre") != "", "an English privateer can't enter a French port in wartime")
	# Brethren of the coast.
	var hostile := 0
	for i in 200:
		p.rng.seed = 900 + i
		var e := {"kind": "pirate", "nation": "England", "personality": "Greedy pirate", "traits": World.PERSONALITIES["Greedy pirate"],
			"ship": Sim.make_ship("brigantine", ""), "crew": 80, "morale": 80.0}
		if Sim.npc_hostile(p, e):
			hostile += 1
	check(hostile == 0, "English pirates leave an English pirate be")

func _test_voyage() -> void:
	var s := Sim.new_game("Trader", "England", 2)
	check(Sim.set_sail(s, "st_johns") == "", "trader can sail to Antigua")
	for i in 80:
		if not s.encounter.is_empty():
			Sim.resolve(s, "flee", {})
		if s.ended or not s.at_sea():
			break
		Sim.sail_day(s)
	check(s.ended or s.location == "st_johns", "voyage reaches port or ends")
	var p := Sim.new_game("Pirate", "England", 3)
	check(Sim.can_sail_to(p, "bridgetown") != "", "pirate barred from Bridgetown")

func _test_roles() -> void:
	# 1675: England at peace, so an English privateer sails under a French marque.
	var pv := Sim.new_game("Privateer", "England", 10)
	check(pv.patron == "France", "1675 English privateer carries a French commission (got %s)" % pv.patron)
	# Trader buys a marque where the governor is at war.
	var t := Sim.new_game("Trader", "France", 11)
	var msg := Sim.office(t, "marque")
	check(t.role == "Privateer" and t.patron == "France", "French trader buys a French marque: " + msg)
	# Peace voids it.
	t.day = int((1678.9 - World.START_YEAR) * 365)
	Sim.rest(t, 1)
	check(t.role == "Trader", "Peace of Nijmegen voids the marque")
	# Navy: free stores at home, can't resign while poor.
	var n := Sim.new_game("Navy", "England", 12)
	check(Sim.store_price(n, "food") == 0.0, "navy victuals free at home")
	var opts := Sim.office_options(n)
	var resign_ok := false
	for o in opts:
		if o["id"] == "resign":
			resign_ok = o["ok"]
	check(not resign_ok, "a penniless lieutenant can't resign and buy a sloop")
	# Turn pirate at sea.
	n.location = ""
	n.voyage = {"from": "bridgetown", "to": "st_johns", "total_nm": 100.0, "done_nm": 10.0}
	Sim.turn_pirate(n)
	check(n.role == "Pirate" and n.owns_ship and n.rep("England") < 0, "deserting with the King's ship")
	# Pirate pardon by bribe in a friendly port.
	var pr := Sim.new_game("Pirate", "England", 13)
	pr.reputation["France"] = 30
	pr.location = "saint_pierre"
	pr.chest = 5000.0
	Sim.office(pr, "pardon")
	check(pr.role == "Trader" and pr.nation == "France" and pr.bounty == 0.0, "pardoned by the French governor")
	# Shipyard.
	var sy := Sim.new_game("Trader", "England", 14)
	sy.chest = 10000.0
	Sim.buy_ship(sy, "brigantine")
	check(sy.ship["cls"] == "brigantine", "bought a brigantine")

func _test_battles() -> void:
	var wins := 0
	for i in 60:
		var s := Sim.new_game("Pirate", "England", 100 + i)
		s.voyage = {"from": "st_thomas", "to": "oranjestad", "total_nm": 100.0, "done_nm": 50.0}
		s.location = ""
		var e := Sim.make_encounter(s)
		e["kind"] = "merchant"
		e["hostile"] = false
		e["ship"] = Sim.make_ship("fluyt", "")
		e["crew"] = 17
		e["morale"] = 45.0
		e["personality"] = "Cautious merchant"
		e["traits"] = World.PERSONALITIES["Cautious merchant"]
		e["nation"] = "Dutch"
		s.encounter = e
		var r := Sim.resolve(s, "attack", {"range": "close", "shot": "grape", "board": true})
		if r.get("outcome", "") == "prize":
			wins += 1
	print("pirate sloop vs fluyt prize rate: %.2f" % (wins / 60.0))
	check(wins >= 50, "a faster pirate sloop runs down and takes a fluyt (got %d/60)" % wins)
	# A sloop can claw off to windward from a frigate.
	var away := 0
	for i in 60:
		var s2 := Sim.new_game("Pirate", "England", 300 + i)
		s2.location = ""
		s2.voyage = {"from": "st_thomas", "to": "oranjestad", "total_nm": 100.0, "done_nm": 50.0}
		var e2 := Sim.make_encounter(s2)
		e2["kind"] = "navy"
		e2["nation"] = "Spain"
		e2["ship"] = Sim.make_ship("frigate", "")
		e2["crew"] = 140
		e2["morale"] = 75.0
		e2["personality"] = "Dutiful navy"
		e2["traits"] = World.PERSONALITIES["Dutiful navy"]
		e2["hostile"] = true
		s2.encounter = e2
		var r2 := Sim.resolve(s2, "flee", {})
		if r2.get("outcome", "") in ["we_escaped", "stalemate"]:
			away += 1
	check(away >= 45, "sloop escapes a frigate most times (got %d/60)" % away)

## His ask: +/- a basket, see where you stand, then approve; say when it's
## room or coin that stops you.
func _test_basket() -> void:
	var s := Sim.new_game("Trader", "England", 21)
	var b := {"sugar": 5.0, "food": 1.0}
	var q := Sim.basket_quote(s, b)
	check(q["ok"] and float(q["spend"]) > 0.0, "a small basket is affordable")
	var chest := s.chest
	Sim.apply_basket(s, b)
	check(absf(s.chest - float(q["chest_after"])) < 1.0, "approve costs what the quote said (%d vs %d)" % [s.chest, q["chest_after"]])
	check(float(s.cargo.get("sugar", 0.0)) >= 5.0 and s.chest < chest, "the goods are aboard")
	var msg := Sim.sell_good(s, "sugar", 2.0)
	check("profit" in msg or "loss" in msg, "a sale says what it made: " + msg)
	# Room: ask for more than the hold takes.
	var big := Sim.basket_room(s, {}, "timber", 9999.0)
	check(big["why"] != "" and float(big["tons"]) <= s.cargo_free() + 0.01, "a hold-full basket says why: " + String(big["why"]))
	s.chest = 1.0
	var poor := Sim.basket_room(s, {}, "silver", 5.0)
	check(poor["why"] == "No coin" and float(poor["tons"]) == 0.0, "an empty chest says No coin (got %s)" % poor["why"])
	s.chest = 1e6
	s.cargo["sugar"] = float(s.cargo.get("sugar", 0.0)) + s.cargo_free()
	var full := Sim.basket_room(s, {}, "cloth", 5.0)
	check(full["why"] == "No room" and float(full["tons"]) == 0.0, "a full hold says No room (got %s)" % full["why"])
	# Selling in the basket frees room for buying.
	var swap := Sim.basket_quote(s, {"sugar": -10.0, "cloth": 10.0})
	check(swap["ok"], "sell 10 and buy 10 fits a full hold")

## Passage days come as a range, and the trade wind makes east slow.
func _test_passage() -> void:
	var s := Sim.new_game("Trader", "England", 31)
	s.location = "willemstad"
	var west := Sim.new_game("Trader", "England", 31)
	var east := Sim.passage(s, "bridgetown")
	var down := Sim.passage(west, "willemstad")
	print("Bridgetown→Willemstad %d–%d d (%s); back %d–%d d (%s)" % [down["lo"], down["hi"], down["wind"], east["lo"], east["hi"], east["wind"]])
	check(east["wind"] == "beating" and down["wind"] == "running", "east is a beat, west a run")
	check(east["hi"] > down["hi"], "beating back east takes longer")
	# The range should hold the real passage most times.
	var inside := 0
	var n := 200
	for i in n:
		var v := Sim.new_game("Trader", "England", 5000 + i)
		var pa := Sim.passage(v, "st_thomas")
		Sim.set_sail(v, "st_thomas")
		var days := 0
		while v.at_sea() and not v.ended and days < 80:
			if not v.encounter.is_empty():
				v.encounter = {}
			Sim.sail_day(v)
			days += 1
		if days >= int(pa["lo"]) and days <= int(pa["hi"]):
			inside += 1
	print("passage range held %d/%d" % [inside, n])
	check(inside >= int(n * 0.85), "passage range holds the real passage ≥85%% (got %d/%d)" % [inside, n])

## All-AI careers with a simple policy per role, to sanity-check the economy.
func _sweep() -> void:
	var setups := [["Trader", "England", ""], ["Pirate", "England", ""], ["Privateer", "England", ""], ["Navy", "England", ""]]
	for st in setups:
		var role: String = st[0]
		var worth := []
		var deaths := 0
		var causes := {}
		var roles_end := {}
		var prizes := 0
		for i in 60:
			var s := Sim.new_game(role, st[1], 1000 + i)
			Policy.play(s, 3 * 365)
			if not s.alive:
				deaths += 1
				var k: String = s.end_reason.substr(0, 28)
				causes[k] = int(causes.get(k, 0)) + 1
			roles_end[s.role] = int(roles_end.get(s.role, 0)) + 1
			prizes += s.prizes_taken + s.pirates_taken
			worth.append(Sim.net_worth(s))
		worth.sort()
		print("%s: median worth %d, p90 %d, dead %d%%, prizes/career %.1f, ended as %s" % [role, worth[30], worth[54],
			deaths * 100 / 60, prizes / 60.0, roles_end])
		print("  causes: ", causes)
