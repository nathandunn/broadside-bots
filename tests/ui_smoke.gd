extends SceneTree
## Drive the UI headless through every screen, including a 3D battle, to
## catch runtime errors.
func _init():
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for role in ["Trader", "Pirate", "Privateer", "Navy"]:
		main._start(role)
		await process_frame
		main.refresh()
		await process_frame
		if role == "Trader":
			main.sail_to("st_johns")
		else:
			main.note(Sim.cruise(main.state, 20))
		await process_frame
		var fought := false
		for i in 40:
			main._sail_until()
			await process_frame
			if not main.state.encounter.is_empty():
				main._act("attack" if role != "Trader" else "flee")
				await process_frame
				if main.view != null:
					# Watch a few frames of the 3D fight, then skip to the end.
					for f in 30:
						await process_frame
					main.view._set_speed(64.0)
					main.view._order({"shot": "grape"})
					main.view._skip()
					for f in 5:
						await process_frame
					main.view.finished.emit()
					await process_frame
					fought = true
			if main.state.ended or not main.state.at_sea():
				break
		main.refresh()
		await process_frame
		print(role, " ok (fought=", fought, "): ", main.state.journal.slice(-2))
	main._new_career()
	await process_frame
	print("UI SMOKE DONE")
	quit()
