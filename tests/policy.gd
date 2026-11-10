class_name Policy
extends RefCounted
## A simple captain for headless career sweeps, one policy per role.

static func play(s: GameState, days: int) -> void:
	var ports := World.PORTS.map(func(p): return p["id"])
	while not s.ended and s.day < days:
		if s.at_sea():
			if not s.encounter.is_empty():
				var e: Dictionary = s.encounter
				var act := "flee" if e["hostile"] else "sail_on"
				var ours := Sim.power(s.ship, s.crew, s.morale)
				var theirs := Sim.power(e["ship"], e["crew"], e["morale"])
				if e["hostile"] and s.role == "Trader" and theirs > 1.5 * ours:
					act = "surrender"
				var fx := Sim.attack_effects(s, e, "prize")
				var orders := {"range": "close", "shot": "grape", "board": true}
				match s.role:
					"Pirate":
						if e["kind"] == "merchant" or (e["kind"] == "privateer" and theirs < ours):
							act = "attack"
					"Privateer":
						if fx["legal"] and e["kind"] in ["merchant", "privateer"] and theirs < ours * 1.2:
							act = "attack"
					"Navy":
						if fx["legal"] and theirs < ours * 1.5:
							act = "attack"
							orders = {"range": "close", "shot": "round", "board": e["kind"] == "merchant"}
				Sim.resolve(s, act, orders)
			else:
				if float(s.ship["hull"]) < float(s.ship["hull_max"]) * 0.6 or Sim.days_of(s, "water") < 8.0:
					Sim.head_home(s)
				Sim.sail_day(s)
			continue
		# In port: sell everything, restock, trade, go.
		for g in s.cargo.keys():
			Sim.sell_good(s, g, float(s.cargo[g]))
		match s.role:
			"Pirate", "Privateer":
				Sim.share_out(s)
				Sim.recruit(s, 20)
			"Navy":
				Sim.recruit(s, int(s.ship["crew_cap"]) - s.crew)
				Sim.bank(s, s.chest)
			_:
				Sim.pay_wages(s)
				Sim.recruit(s, int(s.ship["crew_cap"]) - s.crew)
		if s.role == "Trader" and s.chest < 1500.0:
			Sim.withdraw(s, 1500.0 - s.chest)
		Sim.rest(s, s.rng.randi_range(2, 5))
		# Careen until she's fit to run from a navy.
		var careen := 0
		while s.role in ["Pirate", "Privateer"] and Sim.repair_cost(s) > s.chest and careen < 6 \
				and (float(s.ship["rig"]) < 90.0 or float(s.ship["hull"]) < float(s.ship["hull_max"]) * 0.9):
			Sim.rest(s, 3)
			careen += 1
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
		if s.role in ["Pirate", "Privateer", "Navy"]:
			if Sim.cruise(s, 20) != "":
				return
			continue
		var dest := ""
		for tries in 20:
			var d: String = ports[s.rng.randi_range(0, ports.size() - 1)]
			if tries < 15:
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
