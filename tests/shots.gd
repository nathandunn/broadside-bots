extends SceneTree
## Screenshots for a human look: title, port, encounter, battle.
func snap(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_%s.png" % name)

func _init():
	var w := int(OS.get_environment("SHOT_W"))
	var h := int(OS.get_environment("SHOT_H"))
	var tag := OS.get_environment("SHOT_TAG")
	root.size = Vector2i(w, h)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await snap(tag + "_title")
	main.pick_nation = "England"
	main._start("Trader")
	main.state.basis["sugar"] = 9.0
	main.basket = {"sugar": -10.0, "cloth": 2.0, "food": 1.0}
	main.refresh()
	await snap(tag + "_market")
	(main.panel.get_parent() as ScrollContainer).scroll_vertical = 520
	await snap(tag + "_basket")
	main.basket = {}
	main._start("Privateer")
	await snap(tag + "_port")
	var s: GameState = main.state
	s.location = ""
	s.voyage = {"from": "saint_pierre", "to": "saint_pierre", "total_nm": 2000.0, "done_nm": 100.0, "cruise": true}
	var e := Sim.make_encounter(s)
	e["kind"] = "privateer"
	e["nation"] = "Spain"
	e["ship"] = Sim.make_ship("brigantine", "")
	e["crew"] = 60
	e["morale"] = 70.0
	e["personality"] = "Bold privateer"
	e["traits"] = World.PERSONALITIES["Bold privateer"]
	e["hostile"] = true
	e["text"] = Sim.encounter_text(s, e)
	s.encounter = e
	main.refresh()
	await snap(tag + "_encounter")
	main.orders = {"range": "close", "shot": "round", "board": false, "ram": false}
	main._act("attack")
	var b: Battle = main.view.battle
	# fast-forward until the guns are talking
	while not b.done() and b.events.filter(func(x): return x["type"] == "broadside").size() < 3:
		b.step(1.0)
	b.events.clear()
	main.view.speed = 1.0
	# let the next broadside go off on screen
	var fired := false
	for i in 400:
		b.step(1.0)
		if b.events.filter(func(x): return x["type"] == "broadside").size() > 0 or b.done():
			break
	for i in 30:
		await process_frame
	await snap(tag + "_battle")
	quit()
