extends SceneTree
## Outcome table for set-piece fights under the new battle sim.
func trial(role: String, nation: String, my_cls: String, crew: int, kind: String, their_cls: String, pers: String, action: String, orders: Dictionary, n: int) -> void:
	var tally := {}
	var secs := 0.0
	for i in n:
		var s := Sim.new_game(role, nation, 7000 + i)
		s.ship = Sim.make_ship(my_cls, "x")
		s.crew = crew
		s.location = ""
		s.voyage = {"from": "st_thomas", "to": "oranjestad", "total_nm": 100.0, "done_nm": 50.0}
		var e := Sim.make_encounter(s)
		e["kind"] = kind
		e["nation"] = "Dutch" if kind != "pirate" else "France"
		e["ship"] = Sim.make_ship(their_cls, "")
		e["crew"] = int(e["ship"]["crew_cap"] * (0.7 if kind == "merchant" else 0.88))
		e["personality"] = pers
		e["traits"] = World.PERSONALITIES[pers]
		e["morale"] = 45.0 if kind == "merchant" else 70.0
		e["hostile"] = kind != "merchant"
		s.encounter = e
		var b := Sim.start_battle(s, action, orders)
		b.run()
		secs += b.t
		var k: String = b.outcome
		tally[k] = int(tally.get(k, 0)) + 1
	print("PROBE %-9s %-11s vs %-9s %-11s %-19s %-7s %s  avg %d min" % [role, my_cls, kind, their_cls, pers, action, tally, secs / n / 60.0])

func _init():
	var t0 := Time.get_ticks_msec()
	var atk := {"range": "close", "shot": "grape", "board": true}
	trial("Pirate", "England", "sloop", 50, "merchant", "fluyt", "Cautious merchant", "attack", atk, 100)
	trial("Pirate", "England", "sloop", 50, "merchant", "fluyt", "Stubborn merchant", "attack", atk, 100)
	trial("Pirate", "England", "sloop", 50, "merchant", "merchantman", "Stubborn merchant", "attack", atk, 100)
	trial("Trader", "England", "fluyt", 18, "merchant", "fluyt", "Stubborn merchant", "attack", {"range": "close", "shot": "round", "board": false}, 100)
	trial("Pirate", "England", "sloop", 50, "navy", "frigate", "Dutiful navy", "flee", {}, 100)
	trial("Pirate", "England", "sloop", 50, "navy", "brigantine", "Dutiful navy", "flee", {}, 100)
	trial("Trader", "England", "fluyt", 18, "pirate", "sloop", "Greedy pirate", "flee", {}, 100)
	trial("Navy", "England", "brigantine", 80, "pirate", "sloop", "Greedy pirate", "attack", {"range": "close", "shot": "round", "board": false}, 100)
	trial("Navy", "England", "brigantine", 80, "pirate", "sloop", "Bloodthirsty pirate", "attack", {"range": "close", "shot": "round", "board": true}, 100)
	print("PROBE took %d ms" % (Time.get_ticks_msec() - t0))
	quit()
