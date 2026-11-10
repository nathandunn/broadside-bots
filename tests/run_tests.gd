extends SceneTree
## Headless checks + a small all-AI career sweep.
## Run: godot --headless --path . -s tests/run_tests.gd

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", what)

func _init() -> void:
	_test_markets()
	_test_voyage()
	_test_combat()
	_sweep()
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)

func _test_markets() -> void:
	var s := Sim.new_game("Trader", 1)
	var before := s.chest
	var p := Sim.buy_price(s, s.location, "cloth")
	Sim.buy_good(s, "cloth", 5.0)
	check(s.chest < before, "buying cloth costs coin")
	check(Sim.buy_price(s, s.location, "cloth") > p, "buying raises the price")
	check(Sim.sell_price(s, "bridgetown", "sugar") < Sim.sell_price(s, "oranjestad", "sugar"), "sugar dearer where wanted")
	var d := World.distance_nm(World.port_by_id("bridgetown"), World.port_by_id("willemstad"))
	check(d > 500.0 and d < 600.0, "Bridgetown–Willemstad ~550 nm (got %d)" % d)

func _test_voyage() -> void:
	var s := Sim.new_game("Trader", 2)
	check(Sim.set_sail(s, "st_johns") == "", "trader can sail to Antigua")
	for i in 80:
		if not s.encounter.is_empty():
			Sim.resolve(s, "flee", {})
		if s.ended or not s.at_sea():
			break
		Sim.sail_day(s)
	check(s.ended or s.location == "st_johns", "voyage reaches port or ends")
	var p := Sim.new_game("Pirate", 3)
	check(Sim.can_sail_to(p, "bridgetown") != "", "pirate barred from Bridgetown")

func _test_combat() -> void:
	var wins := 0
	for i in 200:
		var s := Sim.new_game("Pirate", 100 + i)
		s.voyage = {"from": "st_thomas", "to": "oranjestad", "total_nm": 100.0, "done_nm": 50.0}
		s.location = ""
		var e := Sim.make_encounter(s)
		e["kind"] = "merchant"
		e["hostile"] = false
		e["ship"] = Sim.make_ship("fluyt", "")
		e["crew"] = 17
		e["traits"] = World.PERSONALITIES["Cautious merchant"]
		e["nation"] = "Dutch"
		s.encounter = e
		var r := Sim.resolve(s, "attack", {"range": "close", "shot": "grape", "board": true})
		if r.get("outcome", "") == "prize":
			wins += 1
	print("pirate sloop vs fluyt prize rate: %.2f" % (wins / 200.0))
	check(wins > 100, "a pirate sloop usually takes a fluyt")

## All-AI careers with a dumb policy, to sanity-check the economy.
func _sweep() -> void:
	for role in ["Trader", "Pirate"]:
		var worth := []
		var deaths := 0
		var causes := {}
		for i in 100:
			var s := Sim.new_game(role, 1000 + i)
			_play(s, 3 * 365)
			if not s.alive:
				deaths += 1
				var k: String = s.end_reason.substr(0, 28)
				causes[k] = int(causes.get(k, 0)) + 1
			worth.append(Sim.net_worth(s))
		worth.sort()
		print("%s: median worth %d, p90 %d, dead %d%%" % [role, worth[50], worth[90], deaths])
		print("  causes: ", causes)

func _play(s: GameState, days: int) -> void:
	var ports := World.PORTS.map(func(p): return p["id"])
	while not s.ended and s.day < days:
		if s.at_sea():
			if not s.encounter.is_empty():
				var e: Dictionary = s.encounter
				var act := "flee" if e["hostile"] else "sail_on"
				if e["hostile"] and s.role == "Trader" and Sim.power(e["ship"], e["crew"], e["morale"]) > 1.5 * Sim.power(s.ship, s.crew, s.morale):
					act = "surrender"
				if s.role == "Pirate" and e["kind"] == "merchant":
					act = "attack"
				Sim.resolve(s, act, {"range": "close", "shot": "grape", "board": true})
			else:
				if float(s.ship["hull"]) < float(s.ship["hull_max"]) * 0.6 or Sim.days_of(s, "water") < 8.0:
					Sim.head_home(s)
				Sim.sail_day(s)
			continue
		# In port: sell everything, restock, trade, go.
		for g in s.cargo.keys():
			Sim.sell_good(s, g, float(s.cargo[g]))
		if s.role == "Pirate":
			Sim.share_out(s)
			Sim.recruit(s, 20)
		else:
			Sim.pay_wages(s)
			Sim.recruit(s, int(s.ship["crew_cap"]) - s.crew)
		if s.role == "Trader" and s.chest < 1500.0:
			Sim.withdraw(s, 1500.0 - s.chest)
		Sim.rest(s, s.rng.randi_range(2, 5))
		if s.role == "Pirate" and Sim.repair_cost(s) > s.chest:
			Sim.rest(s, 6)
		if s.role == "Trader":
			Sim.pay_wages(s)
		Sim.repair(s)
		var need_food := s.crew * Sim.FOOD_PER_MAN * 45.0 - float(s.stores.get("food", 0.0))
		var need_water := s.crew * Sim.WATER_PER_MAN * 45.0 - float(s.stores.get("water", 0.0))
		if need_food > 0.0:
			Sim.buy_store(s, "food", ceil(need_food))
		if need_water > 0.0:
			Sim.buy_store(s, "water", ceil(need_water))
		if float(s.stores.get("powder", 0.0)) < 1.0:
			Sim.buy_store(s, "powder", 1.0)
		var dest := ""
		if s.role == "Pirate":
			if Sim.cruise(s, 20) != "":
				return
			continue
		for tries in 20:
			var d: String = ports[s.rng.randi_range(0, ports.size() - 1)]
			if s.role == "Trader" and tries < 15:
				var wants: Array = World.port_by_id(d)["wants"]
				var here_p: Array = World.port_by_id(s.location)["produces"]
				var ok := false
				for g in here_p:
					if g in wants:
						ok = true
				if not ok:
					continue
			if Sim.can_sail_to(s, d) == "":
				dest = d
				break
		if dest == "":
			return
		if s.role == "Trader":
			# Buy whatever this port produces cheapest.
			var here := World.port_by_id(s.location)
			var budget: float = max(0.0, s.chest - 600.0)
			for g in here["produces"]:
				var tons: float = min(max(0.0, s.cargo_free() - 5.0) / max(1, here["produces"].size()), floor(budget / here["produces"].size() / Sim.buy_price(s, s.location, g)))
				Sim.buy_good(s, g, tons)
			if s.chest > 3000.0:
				Sim.bank(s, s.chest - 2000.0)
		if Sim.set_sail(s, dest) != "":
			return
